"""Memoria personal de Matix: lo que sabe del usuario.

Hechos duraderos (quién es, metas, personas, situación, preferencias,
contexto de proyectos) que viven en la tabla `memoria`. Dos vías de uso:

- **Siempre inyectado**: los hechos `esencial=true` se arman en un bloque
  compacto ("lo que sé de ti") que el chat mete en el contexto, junto a
  `contexto_vivo`, para que todo salga personalizado.
- **RAG**: cualquier hecho con embedding se puede recuperar por relevancia
  con `buscar` (tool `buscar_memoria`), para no inflar el prompt con detalle.

El embedding es best-effort: si OpenAI falla, el hecho igual se guarda, se
inyecta (si es esencial) y se lista; solo no aparece en la búsqueda RAG.
"""
from __future__ import annotations

import logging
from typing import Any

from ..db import Postgrest
from . import llm

logger = logging.getLogger("matix.memoria")

# Tope de hechos esenciales en el bloque inyectado. Generoso: el bloque debe
# ser compacto, no un volcado. Lo que pase de acá vive solo en RAG.
_MAX_ESENCIALES = 60


async def _embebir(texto: str) -> list[float] | None:
    """Embebe un texto; None si falla (best-effort, no rompe el guardado)."""
    texto = (texto or "").strip()
    if not texto:
        return None
    try:
        [emb] = await llm.embebir([texto])
        return emb
    except Exception:  # noqa: BLE001
        logger.exception("memoria: no pude embeber")
        return None


_COLS = "id,contenido,categoria,esencial,creado_en,actualizado_en"


async def listar(db: Postgrest) -> list[dict[str, Any]]:
    """Todos los hechos (para la pantalla 'Sobre mí'). Sin el `embedding`,
    que es pesado y no se muestra."""
    return await db.list("memoria", order="categoria.asc", select=_COLS)


async def bloque_memoria(db: Postgrest) -> str:
    """Bloque compacto 'lo que sé de ti' con los hechos ESENCIALES, agrupados
    por categoría. Cadena vacía si no hay ninguno."""
    filas = await db.list(
        "memoria",
        raw_filters={"esencial": "is.true"},
        limit=_MAX_ESENCIALES,
        select="contenido,categoria",
    )
    if not filas:
        return ""
    por_cat: dict[str, list[str]] = {}
    for f in filas:
        cat = (f.get("categoria") or "general").strip() or "general"
        contenido = (f.get("contenido") or "").strip()
        if contenido:
            por_cat.setdefault(cat, []).append(contenido)
    if not por_cat:
        return ""
    lineas = [
        "LO QUE SÉ DE TI (memoria personal del usuario). Úsalo para "
        "personalizar tus respuestas y dar tips aterrizados; NO lo recites de "
        "corrido ni lo menciones salvo que venga al caso:",
    ]
    for cat in sorted(por_cat):
        lineas.append(f"- {cat}:")
        for c in por_cat[cat]:
            lineas.append(f"  · {c}")
    return "\n".join(lineas)


async def recordar(
    db: Postgrest,
    *,
    contenido: str,
    categoria: str | None = None,
    esencial: bool = True,
) -> dict[str, Any]:
    """Guarda un hecho nuevo. Embebe best-effort para que sea buscable."""
    contenido = (contenido or "").strip()
    payload: dict[str, Any] = {"contenido": contenido, "esencial": bool(esencial)}
    cat = (categoria or "").strip()
    if cat:
        payload["categoria"] = cat
    emb = await _embebir(contenido)
    if emb is not None:
        payload["embedding"] = emb
    return await db.insert("memoria", payload)


async def actualizar(
    db: Postgrest,
    *,
    memoria_id: str,
    contenido: str | None = None,
    categoria: str | None = None,
    esencial: bool | None = None,
) -> dict[str, Any] | None:
    """Actualiza un hecho. Si cambia el contenido, re-embebe (best-effort)."""
    payload: dict[str, Any] = {}
    if contenido is not None:
        payload["contenido"] = contenido.strip()
    if categoria is not None:
        payload["categoria"] = categoria.strip() or None
    if esencial is not None:
        payload["esencial"] = bool(esencial)
    if not payload:
        return await db.get("memoria", memoria_id)
    if "contenido" in payload:
        # Re-embeber con el nuevo contenido (puede quedar None si falla).
        payload["embedding"] = await _embebir(payload["contenido"])
    return await db.update("memoria", memoria_id, payload)


async def olvidar(db: Postgrest, *, memoria_id: str) -> bool:
    """Borra un hecho (permanente: la memoria no tiene papelera)."""
    return await db.delete("memoria", memoria_id)


async def buscar(
    db: Postgrest, *, consulta: str, top_k: int = 5
) -> list[dict[str, Any]]:
    """Recupera hechos por similitud semántica a `consulta` (RAG)."""
    emb = await _embebir(consulta)
    if emb is None:
        return []
    return await db.rpc(
        "buscar_memoria", {"query_embedding": emb, "match_count": top_k}
    )
