"""Backfill: genera embeddings para los apuntes que aún no tienen
chunk (Capa 3 Paso 1).

Uso:

    cd cerebro
    uv run --env-file .env python scripts/embed_apuntes.py

Indempotente. Se puede correr varias veces — solo procesa apuntes
sin chunks. Excluye los que están en la papelera. Imprime un
resumen al final.

Si en el futuro se cambia el modelo de embeddings (p.ej. de
text-embedding-3-small a -large), hay que purgar `apunte_chunks`
y volver a correr este script — los vectores tienen otras
dimensiones y no se pueden mezclar.
"""
from __future__ import annotations

import asyncio
import sys
from pathlib import Path

# Permitir `from app.…` desde la raíz del módulo.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.db import Postgrest  # noqa: E402
from app.matix.indexador import indexar_apunte  # noqa: E402


async def main() -> None:
    db = Postgrest()
    try:
        # Traer apuntes NO eliminados.
        apuntes = await db.list(
            "apuntes",
            raw_filters={"eliminado_en": "is.null"},
        )
        print(f"apuntes activos: {len(apuntes)}")

        # Traer los apunte_ids que ya tienen al menos un chunk.
        chunks = await db.list("apunte_chunks", limit=10_000)
        con_chunks = {c["apunte_id"] for c in chunks}
        pendientes = [a for a in apuntes if a["id"] not in con_chunks]
        print(f"apuntes sin chunks: {len(pendientes)}")

        for i, ap in enumerate(pendientes, start=1):
            titulo_corto = (ap.get("titulo") or "(sin título)")[:50]
            print(f"  [{i}/{len(pendientes)}] {titulo_corto}…", end=" ", flush=True)
            try:
                await indexar_apunte(db, ap)
                print("ok")
            except Exception as e:  # noqa: BLE001
                print(f"FALLÓ: {type(e).__name__}: {e}")

        if not pendientes:
            print("nada que hacer — todos los apuntes ya están indexados.")
    finally:
        await db.aclose()


if __name__ == "__main__":
    asyncio.run(main())
