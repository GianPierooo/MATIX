"""Config de los nudges intensos de tareas (Push Capa 3b).

- `GET /nudges` — lee la config (maestro on/off, silencio, disponibilidad).
- `PATCH /nudges` — la cambia. La app sincroniza acá el maestro, las horas
  de silencio y la disponibilidad por día; el scheduler las respeta.

El apagado POR TAREA no vive aquí: es la columna `tareas.nudges_silenciada`
(se cambia con el PATCH normal de la tarea).
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status

from ..db import Postgrest, get_db
from ..schemas.nudges import NudgesConfigRead, NudgesConfigUpdate
from ..security import require_api_key

router = APIRouter(
    prefix="/nudges",
    tags=["nudges"],
    dependencies=[Depends(require_api_key)],
)

TABLE = "config_nudges"


async def _fila(db: Postgrest) -> dict:
    filas = await db.list(TABLE, limit=1)
    if not filas:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Config de nudges no encontrada. ¿Aplicaste la migración 0019?",
        )
    return filas[0]


@router.get("", response_model=NudgesConfigRead)
async def obtener(db: Postgrest = Depends(get_db)) -> dict:
    return await _fila(db)


@router.patch("", response_model=NudgesConfigRead)
async def actualizar(
    body: NudgesConfigUpdate, db: Postgrest = Depends(get_db)
) -> dict:
    fila = await _fila(db)
    payload = body.model_dump(exclude_unset=True)
    if not payload:
        return fila
    actualizado = await db.update(TABLE, fila["id"], payload)
    return actualizado if actualizado is not None else fila
