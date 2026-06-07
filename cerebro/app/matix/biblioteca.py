"""Biblioteca de material de aprendizaje (Fase 1).

Store SEPARADO de los apuntes (el inbox de ideas). Acá vive el material
que las skills consumen: documentos troceados y embebidos, etiquetados
por `skill` (carpeta, ej. 'calistenia') y `bloque` (archivo/etapa, ej.
'bloque_3').

- `ingestar_material`: reemplaza (idempotente) el material de un
  `skill`+`bloque` por las piezas nuevas. Re-ingestar el mismo skill+bloque
  NO duplica: borra lo viejo y mete lo nuevo.
- `buscar_material`: similarity search, con filtros opcionales por skill
  y bloque. Es lo que usa Matix para traer "el bloque 3 de calistenia"
  sin mezclarlo con la búsqueda de apuntes.

Solo este store toca `material_chunks`; los apuntes siguen en su propio
RAG (`apunte_chunks`, ver `indexador.py`).
"""
from __future__ import annotations

from typing import Any

from ..db import Postgrest
from . import llm

TABLE = "material_chunks"


async def ingestar_material(
    db: Postgrest,
    *,
    skill: str,
    bloque: str,
    fuente: str | None,
    piezas: list[str],
) -> dict[str, int]:
    """Reemplaza el material de (`skill`, `bloque`) por `piezas`.

    Idempotente: primero borra todos los chunks de ese skill+bloque
    (devuelve cuántos), luego embebe e inserta las piezas nuevas. Así
    re-ingestar un documento no acumula duplicados.

    Las piezas vacías se ignoran. Si no queda ninguna, solo borra (sirve
    para "vaciar" un bloque).
    """
    skill = skill.strip()
    bloque = bloque.strip()
    if not skill or not bloque:
        raise ValueError("skill y bloque son obligatorios")

    # 1) Borrar lo previo de este skill+bloque (idempotencia).
    reemplazados = await db.delete_where(
        TABLE, filters={"skill": skill, "bloque": bloque}
    )

    # 2) Normalizar piezas.
    textos = [p.strip() for p in piezas if p and p.strip()]
    if not textos:
        return {"creados": 0, "reemplazados": reemplazados}

    # 3) Embebir todas en una llamada (mismo modelo que el RAG de apuntes).
    # Si no hay crédito de embeddings, la ingesta se pausa con un mensaje
    # honesto — pero NO tumba el cerebro ni el chat (que no la necesita en vivo).
    embeddings = await llm.embebir_seguro(textos)
    if embeddings is None:
        raise RuntimeError(
            "ingesta en pausa: sin crédito de embeddings (OpenAI). "
            "El material no se indexó; reintenta cuando haya saldo."
        )

    # 4) Insertar en orden.
    for orden, (texto, emb) in enumerate(zip(textos, embeddings)):
        await db.insert(
            TABLE,
            {
                "skill": skill,
                "bloque": bloque,
                "fuente": fuente,
                "orden": orden,
                "contenido": texto,
                "embedding": emb,
            },
        )
    return {"creados": len(textos), "reemplazados": reemplazados}


async def buscar_material(
    db: Postgrest,
    *,
    consulta: str,
    skill: str | None = None,
    bloque: str | None = None,
    top_k: int = 5,
) -> list[dict[str, Any]]:
    """Busca en la biblioteca por similitud semántica, opcionalmente
    acotando a un `skill` y/o `bloque`. Devuelve filas
    `{skill, bloque, fuente, fragmento, distancia}`.

    La distancia coseno va de 0 (idéntico) a ~2 (opuesto)."""
    embs = await llm.embebir_seguro([consulta])
    if not embs:
        return []  # sin crédito de embeddings → sin resultados, el chat sigue
    return await db.rpc(
        "buscar_material_chunks",
        {
            "query_embedding": embs[0],
            "match_count": top_k,
            "filtro_skill": (skill or None),
            "filtro_bloque": (bloque or None),
        },
    )
