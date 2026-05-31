"""Config de los rituales por push (Push Capa 3a + repaso semanal).

- `GET /rituales` — lee la config de los rituales (briefing, cierre,
  repaso).
- `PATCH /rituales/{ritual}` — cambia on/off, la hora y (para el repaso
  semanal) el día de la semana.

El scheduler del cerebro (matix/recordatorios.py) usa esta config para
disparar los push a la hora correcta (America/Lima).
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status

from ..db import Postgrest, get_db
from ..schemas.rituales import RitualConfigRead, RitualConfigUpdate
from ..security import require_api_key

router = APIRouter(
    prefix="/rituales",
    tags=["rituales"],
    dependencies=[Depends(require_api_key)],
)

TABLE = "config_rituales"
_RITUALES = ("briefing", "cierre", "repaso")


@router.get("", response_model=list[RitualConfigRead])
async def listar(db: Postgrest = Depends(get_db)) -> list[dict]:
    return await db.list(TABLE, order="ritual.asc")


@router.patch("/{ritual}", response_model=RitualConfigRead)
async def actualizar(
    ritual: str, body: RitualConfigUpdate, db: Postgrest = Depends(get_db)
) -> dict:
    if ritual not in _RITUALES:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Ritual desconocido: {ritual}.",
        )
    filas = await db.list(TABLE, filters={"ritual": ritual}, limit=1)
    if not filas:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ritual no encontrado. ¿Aplicaste la migración 0018?",
        )
    payload = body.model_dump(exclude_unset=True)
    if not payload:
        return filas[0]
    actualizado = await db.update(TABLE, filas[0]["id"], payload)
    return actualizado if actualizado is not None else filas[0]
