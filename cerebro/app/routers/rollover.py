"""Router del ROLLOVER de tareas no cumplidas (Capa 8).

Expone lo que `app.matix.rollover` calcula: las propuestas de reprogramación de
lo no cumplido (al siguiente hueco libre) + el flag honesto de sobrecarga, y el
endpoint para aplicar la decisión del usuario (acepto / otro día / lo suelto).

La app lo surfacea tocable por el robot-compañero; nada se mueve en silencio.
"""
from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..db import Postgrest, get_db
from ..matix import rollover
from ..security import require_api_key

router = APIRouter(
    prefix="/rollover",
    tags=["rollover"],
    dependencies=[Depends(require_api_key)],
)


class DecisionRollover(BaseModel):
    tarea_id: str
    # 'aceptar' | 'otro_dia' | 'soltar'
    decision: str


@router.get("")
async def obtener_rollover(db: Postgrest = Depends(get_db)) -> dict:
    """Propuestas de reprogramación para lo no cumplido + flag de sobrecarga.
    Determinístico (se recalcula al vuelo); no muta nada."""
    return await rollover.proponer_rollover(
        db, ahora=datetime.now(timezone.utc), hasta_fin_de_hoy=True
    )


@router.post("/decidir")
async def decidir_rollover(
    body: DecisionRollover, db: Postgrest = Depends(get_db)
) -> dict:
    """Aplica la decisión del usuario sobre una tarea no cumplida."""
    return await rollover.aplicar_rollover(
        db, tarea_id=body.tarea_id, decision=body.decision
    )
