"""Cierre del día — ritual nocturno del Documento Maestro.

Modelo: una fila por día con la lista de cosas que sí hice. Si POST
llega para un día que ya tiene cierre, se actualiza el existente
(UPSERT por la UNIQUE de `fecha`).
"""
from __future__ import annotations

from datetime import date
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status

from ..db import Postgrest, get_db
from ..schemas.cierres_dia import (
    CierreDiaCreate,
    CierreDiaRead,
    CierreDiaUpdate,
)
from ..security import require_api_key

router = APIRouter(
    prefix="/cierres_dia",
    tags=["cierres_dia"],
    dependencies=[Depends(require_api_key)],
)

TABLE = "cierres_dia"


@router.get("", response_model=list[CierreDiaRead])
async def listar(
    fecha: date | None = Query(default=None),
    db: Postgrest = Depends(get_db),
) -> list[dict]:
    """Lista los cierres. `?fecha=YYYY-MM-DD` devuelve solo ese día."""
    return await db.list(
        TABLE,
        order="fecha.desc",
        filters={"fecha": fecha.isoformat()} if fecha else None,
    )


@router.get("/{cierre_id}", response_model=CierreDiaRead)
async def obtener(cierre_id: UUID, db: Postgrest = Depends(get_db)) -> dict:
    row = await db.get(TABLE, str(cierre_id))
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Cierre no encontrado",
        )
    return row


@router.post(
    "", response_model=CierreDiaRead, status_code=status.HTTP_201_CREATED
)
async def crear_o_sobreescribir(
    body: CierreDiaCreate, db: Postgrest = Depends(get_db)
) -> dict:
    """Si la fecha ya tiene cierre, actualiza el existente en lugar
    de fallar por la UNIQUE. Idempotente."""
    existentes = await db.list(
        TABLE, filters={"fecha": body.fecha.isoformat()}, limit=1
    )
    payload = body.model_dump(mode="json", exclude_none=True)
    if existentes:
        actual = existentes[0]
        return await db.update(TABLE, actual["id"], payload) or actual
    return await db.insert(TABLE, payload)


@router.patch("/{cierre_id}", response_model=CierreDiaRead)
async def actualizar(
    cierre_id: UUID,
    body: CierreDiaUpdate,
    db: Postgrest = Depends(get_db),
) -> dict:
    payload = body.model_dump(mode="json", exclude_unset=True)
    row = await db.update(TABLE, str(cierre_id), payload)
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Cierre no encontrado",
        )
    return row


@router.delete("/{cierre_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar(cierre_id: UUID, db: Postgrest = Depends(get_db)) -> None:
    if not await db.delete(TABLE, str(cierre_id)):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Cierre no encontrado",
        )
