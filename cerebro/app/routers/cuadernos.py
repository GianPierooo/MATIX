from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from ..db import Postgrest, get_db
from ..schemas.cuadernos import CuadernoCreate, CuadernoRead, CuadernoUpdate
from ..security import require_api_key

router = APIRouter(
    prefix="/cuadernos",
    tags=["cuadernos"],
    dependencies=[Depends(require_api_key)],
)

TABLE = "cuadernos"


@router.get("", response_model=list[CuadernoRead])
async def listar(db: Postgrest = Depends(get_db)) -> list[dict]:
    return await db.list(TABLE, order="nombre.asc")


@router.get("/{cuaderno_id}", response_model=CuadernoRead)
async def obtener(cuaderno_id: UUID, db: Postgrest = Depends(get_db)) -> dict:
    row = await db.get(TABLE, str(cuaderno_id))
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Cuaderno no encontrado")
    return row


@router.post("", response_model=CuadernoRead, status_code=status.HTTP_201_CREATED)
async def crear(body: CuadernoCreate, db: Postgrest = Depends(get_db)) -> dict:
    return await db.insert(TABLE, body.model_dump(mode="json", exclude_none=True))


@router.patch("/{cuaderno_id}", response_model=CuadernoRead)
async def actualizar(
    cuaderno_id: UUID, body: CuadernoUpdate, db: Postgrest = Depends(get_db)
) -> dict:
    payload = body.model_dump(mode="json", exclude_unset=True)
    row = await db.update(TABLE, str(cuaderno_id), payload)
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Cuaderno no encontrado")
    return row


@router.delete("/{cuaderno_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar(cuaderno_id: UUID, db: Postgrest = Depends(get_db)) -> None:
    if not await db.delete(TABLE, str(cuaderno_id)):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Cuaderno no encontrado")
