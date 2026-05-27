from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from ..db import Postgrest, get_db
from ..schemas.sesiones_clase import (
    SesionClaseCreate,
    SesionClaseRead,
    SesionClaseUpdate,
)
from ..security import require_api_key

router = APIRouter(
    prefix="/sesiones-clase",
    tags=["sesiones_clase"],
    dependencies=[Depends(require_api_key)],
)

TABLE = "sesiones_clase"


@router.get("", response_model=list[SesionClaseRead])
async def listar(db: Postgrest = Depends(get_db)) -> list[dict]:
    return await db.list(TABLE, order="dia_semana.asc,hora_inicio.asc")


@router.get("/{sesion_id}", response_model=SesionClaseRead)
async def obtener(sesion_id: UUID, db: Postgrest = Depends(get_db)) -> dict:
    row = await db.get(TABLE, str(sesion_id))
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sesión no encontrada")
    return row


@router.post("", response_model=SesionClaseRead, status_code=status.HTTP_201_CREATED)
async def crear(body: SesionClaseCreate, db: Postgrest = Depends(get_db)) -> dict:
    return await db.insert(TABLE, body.model_dump(mode="json", exclude_none=True))


@router.patch("/{sesion_id}", response_model=SesionClaseRead)
async def actualizar(
    sesion_id: UUID, body: SesionClaseUpdate, db: Postgrest = Depends(get_db)
) -> dict:
    payload = body.model_dump(mode="json", exclude_unset=True)
    row = await db.update(TABLE, str(sesion_id), payload)
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sesión no encontrada")
    return row


@router.delete("/{sesion_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar(sesion_id: UUID, db: Postgrest = Depends(get_db)) -> None:
    if not await db.delete(TABLE, str(sesion_id)):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sesión no encontrada")
