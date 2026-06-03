"""Backfill: indexa el historial de conversaciones existente en la memoria
conversacional (Capa Memoria · recall semántico de conversaciones).

Uso:

    cd cerebro
    uv run --env-file .env python scripts/embed_historial.py

Idempotente. Solo procesa conversaciones que aún no tienen chunks en
`memoria_conversacional`. Lee los mensajes reales de `mensajes_chat`, los trocea
con la MISMA lógica que el indexado incremental (`construir_chunks`) y los
embebe con el mismo modelo (text-embedding-3-small). Imprime un resumen.

Nota: como la persistencia de conversaciones recién se introduce, la primera
corrida probablemente no encuentre historial previo (0 chunks) — y está bien:
el recall empieza a poblarse hacia adelante con cada conversación nueva.
"""
from __future__ import annotations

import asyncio
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.db import Postgrest  # noqa: E402
from app.matix import llm  # noqa: E402
from app.matix.memoria_conversacional import construir_chunks  # noqa: E402


async def main() -> None:
    db = Postgrest()
    total_chunks = 0
    try:
        mensajes = await db.list(
            "mensajes_chat", order="creado_en.asc", limit=100_000
        )
        print(f"mensajes en historial: {len(mensajes)}")

        ya = await db.list("memoria_conversacional", select="conversacion_id", limit=100_000)
        indexadas = {c["conversacion_id"] for c in ya}

        por_conv: dict[str, list[dict]] = defaultdict(list)
        for m in mensajes:
            por_conv[m["conversacion_id"]].append(m)

        pendientes = {c: ms for c, ms in por_conv.items() if c not in indexadas}
        print(f"conversaciones: {len(por_conv)} · sin indexar: {len(pendientes)}")

        for i, (conv_id, ms) in enumerate(pendientes.items(), start=1):
            chunks = construir_chunks(ms)
            if not chunks:
                continue
            embeddings = await llm.embebir([c["contenido"] for c in chunks])
            for c, emb in zip(chunks, embeddings):
                fecha = c["fecha"]
                await db.insert(
                    "memoria_conversacional",
                    {
                        "conversacion_id": conv_id,
                        "contenido": c["contenido"],
                        "fecha": fecha if isinstance(fecha, str) else fecha.isoformat(),
                        "n_mensajes": c["n_mensajes"],
                        "embedding": emb,
                    },
                )
            total_chunks += len(chunks)
            print(f"  [{i}/{len(pendientes)}] conv {conv_id[:8]}… → {len(chunks)} chunks")

        print(f"\nlisto · chunks embebidos: {total_chunks}")
    finally:
        await db.aclose()


if __name__ == "__main__":
    asyncio.run(main())
