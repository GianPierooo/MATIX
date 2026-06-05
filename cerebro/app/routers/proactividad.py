"""Dial del motor de proactividad (Capa 8).

- `GET /proactividad` — lee la config (activo, nivel, anticipación).
- `PATCH /proactividad` — la cambia. La app sincroniza acá cuán proactivo es
  Matix (suave/equilibrado/exigente); el scheduler lo respeta en cada tick.

Los frenos (tope diario, silencio, dedup, anti-fatiga) viven en el código del
motor, no en este dial: el usuario sube/baja la intensidad, nunca apaga la
contención.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status

from ..db import Postgrest, get_db
from ..schemas.proactividad import ProactividadConfigRead, ProactividadConfigUpdate
from ..security import require_api_key

router = APIRouter(
    prefix="/proactividad",
    tags=["proactividad"],
    dependencies=[Depends(require_api_key)],
)

TABLE = "config_proactividad"


async def _fila(db: Postgrest) -> dict:
    filas = await db.list(TABLE, limit=1)
    if not filas:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Config de proactividad no encontrada. ¿Aplicaste la migración 0037?",
        )
    return filas[0]


@router.get("", response_model=ProactividadConfigRead)
async def obtener(db: Postgrest = Depends(get_db)) -> dict:
    return await _fila(db)


@router.patch("", response_model=ProactividadConfigRead)
async def actualizar(
    body: ProactividadConfigUpdate, db: Postgrest = Depends(get_db)
) -> dict:
    fila = await _fila(db)
    payload = body.model_dump(exclude_unset=True)
    if not payload:
        return fila
    actualizado = await db.update(TABLE, fila["id"], payload)
    return actualizado if actualizado is not None else fila
