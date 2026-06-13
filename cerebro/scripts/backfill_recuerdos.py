"""Backfill de la memoria unificada `recuerdos` (Capa 3 · RAG).

Indexa lo que YA existe en el hub (tareas, notas, proyectos, universidad) a la
tienda semántica `recuerdos`, para que el recall automático del chat funcione
desde el primer día — no solo con lo que se cree de ahora en adelante.

Idempotente: `recuerdos.indexar` salta por hash lo que no cambió, así que
re-correrlo es barato y seguro. Best-effort por entidad (si una falla, sigue).

Uso (desde cerebro/, con el .env cargado):
    uv run python scripts/backfill_recuerdos.py

Filtra la PAPELERA: tareas/notas/eventos con `eliminado_en` NO se indexan
(Matix no debe recordar lo que el usuario borró). Proyectos no tienen papelera
(su ciclo es activo/aparcado/terminado): se indexan todos, con el estado en el
texto — los aparcados/terminados son contexto histórico legítimo, no basura.
"""
from __future__ import annotations

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).resolve().parent.parent / ".env")
except Exception:  # noqa: BLE001
    pass

from app.db import db  # noqa: E402
from app.matix import recuerdos  # noqa: E402

_LIMIT = 5000  # techo holgado para el volumen de un solo usuario


async def _indexar_lista(tipo: str, filas: list[dict], *, subtipo: str | None = None) -> dict[str, int]:
    cuenta = {"indexado": 0, "sin_cambio": 0, "sin_embedding": 0, "vacio": 0, "error": 0, "otro": 0}
    for fila in filas:
        est = await recuerdos.indexar_entidad(db, tipo, fila, subtipo=subtipo)
        cuenta[est if est in cuenta else "otro"] = cuenta.get(est if est in cuenta else "otro", 0) + 1
    return cuenta


async def main() -> None:
    print("Backfill de recuerdos — leyendo el hub…")

    tareas = await db.list("tareas", raw_filters={"eliminado_en": "is.null"}, limit=_LIMIT)
    notas = await db.list("apuntes", raw_filters={"eliminado_en": "is.null"}, limit=_LIMIT)
    proyectos = await db.list("proyectos", limit=_LIMIT)
    cursos = await db.list("cursos", limit=_LIMIT)
    evaluaciones = await db.list("evaluaciones", limit=_LIMIT)
    eventos = await db.list("eventos", raw_filters={"eliminado_en": "is.null"}, limit=_LIMIT)

    print(f"  tareas={len(tareas)} notas={len(notas)} proyectos={len(proyectos)} "
          f"cursos={len(cursos)} evaluaciones={len(evaluaciones)} eventos={len(eventos)}")

    lotes = [
        ("tarea", tareas, None),
        ("nota", notas, None),
        ("proyecto", proyectos, None),
        ("universidad", cursos, "curso"),
        ("universidad", evaluaciones, "evaluacion"),
        ("universidad", eventos, "evento"),
    ]
    total = {"indexado": 0, "sin_cambio": 0, "sin_embedding": 0, "vacio": 0, "error": 0, "otro": 0}
    for tipo, filas, sub in lotes:
        c = await _indexar_lista(tipo, filas, subtipo=sub)
        etiqueta = f"{tipo}/{sub}" if sub else tipo
        print(f"  {etiqueta:24} -> {c}")
        for k, v in c.items():
            total[k] = total.get(k, 0) + v

    print(f"\nTOTAL: {total}")
    print("Listo. El chat ya recupera estos recuerdos automáticamente.")
    await db.aclose()


if __name__ == "__main__":
    asyncio.run(main())
