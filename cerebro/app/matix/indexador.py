"""Indexador semántico de apuntes (Capa 3 Paso 1).

Cada vez que se crea o edita un apunte, llamamos a `indexar_apunte`
acá. La función:

1. Borra los chunks viejos del apunte (si los había).
2. Trocea el contenido si hace falta (en Paso 1, un solo chunk por
   apunte — título + contenido juntos).
3. Pide los embeddings a OpenAI vía `llm.embebir`.
4. Inserta los chunks en `apunte_chunks`.

Decisiones:

- Un solo chunk por apunte por ahora. `text-embedding-3-small`
  acepta ~8000 tokens (~25k chars), suficiente para apuntes
  normales. Si en el futuro hay apuntes que pasen eso, partimos
  por párrafos.
- El soft-delete del apunte no toca los chunks — al restaurar el
  apunte vuelven a aparecer en búsqueda sin re-embeber. Si el
  apunte se purga permanente, la FK `ON DELETE CASCADE` borra los
  chunks solos.
- Cuando indexamos, NO chequeamos `eliminado_en`. El caller del
  router solo llama acá tras un POST/PATCH, que solo pasan sobre
  apuntes activos. Si en el futuro hubiera un caso donde se quiera
  forzar indexación de un soft-deleted, el `aceptar_eliminado=True`
  cubre eso (lo usa el script de backfill por defecto se queda en
  False para no resucitar contenido borrado).
"""
from __future__ import annotations

from typing import Any

from ..db import Postgrest
from . import llm

# Cuánto recortamos el contenido al guardar en el chunk. Aunque el
# modelo acepta ~25k chars, nuestros apuntes típicos no se acercan;
# pero ponemos un techo para no embeber cosas absurdas si algo en
# el futuro mete un binario o un paste enorme.
_MAX_CHARS_POR_CHUNK = 24_000


def _texto_a_indexar(apunte: dict[str, Any]) -> str:
    """Combina título + etiquetas + contenido en un solo string.
    Las etiquetas suman contexto (p.ej. "examen", "cálculo") sin
    costar muchos tokens."""
    partes: list[str] = []
    if apunte.get("titulo"):
        partes.append(str(apunte["titulo"]).strip())
    etiquetas = apunte.get("etiquetas") or []
    if etiquetas:
        partes.append("Etiquetas: " + ", ".join(str(e) for e in etiquetas))
    contenido = (apunte.get("contenido") or "").strip()
    if contenido:
        partes.append(contenido)
    texto = "\n\n".join(partes)
    return texto[:_MAX_CHARS_POR_CHUNK]


async def indexar_apunte(db: Postgrest, apunte: dict[str, Any]) -> None:
    """Re-genera los chunks del apunte (borra los viejos, mete los
    nuevos). Idempotente.

    Si el apunte está vacío (sin título, sin contenido), borra los
    chunks y no embebe nada. No tiene sentido tener un vector que
    represente un apunte vacío en el espacio.
    """
    apunte_id = str(apunte["id"])

    # 1) Borrar chunks viejos del apunte (puede ser 0).
    await db.delete_where(
        "apunte_chunks", filters={"apunte_id": apunte_id}
    )

    texto = _texto_a_indexar(apunte)
    if not texto:
        return

    # 2) Embebir. En Paso 1, un solo chunk por apunte (título +
    # etiquetas + contenido juntos). text-embedding-3-small acepta
    # ~8k tokens, y nuestros apuntes típicos no se acercan.
    # Best-effort: si no hay crédito de embeddings, el apunte YA se guardó
    # (esto es solo el índice RAG); no tumbamos la creación.
    embs = await llm.embebir_seguro([texto])
    if not embs:
        return
    [emb] = embs

    # 3) Insertar. pgvector acepta el embedding como una lista de
    # floats — PostgREST la serializa como JSON y el cast implícito
    # del tipo `vector` la parsea.
    await db.insert(
        "apunte_chunks",
        {
            "apunte_id": apunte_id,
            "orden": 0,
            "contenido": texto,
            "embedding": emb,
        },
    )


async def buscar_apuntes(
    db: Postgrest,
    *,
    consulta: str,
    top_k: int = 5,
) -> list[dict[str, Any]]:
    """Busca apuntes por similitud semántica a `consulta`.

    1. Embebe la consulta con el mismo modelo que indexó los apuntes
       (text-embedding-3-small → 1536 dims).
    2. Llama a la función SQL `buscar_apunte_chunks` vía RPC. Esa
       función ordena por distancia coseno (`<=>`), filtra apuntes
       en la papelera y devuelve los top-K con título + fragmento.

    Devuelve filas `{apunte_id, titulo, fragmento, distancia}`. La
    distancia va de 0 (idéntico) a ~2 (opuesto); valores típicos
    de un match razonable están entre 0.2 y 0.6.
    """
    embs = await llm.embebir_seguro([consulta])
    if not embs:
        return []  # sin crédito de embeddings → búsqueda RAG vacía, chat sigue
    return await db.rpc(
        "buscar_apunte_chunks",
        {"query_embedding": embs[0], "match_count": top_k},
    )
