"""CRUD de `movimientos` (Finanzas-1).

Ingresos y gastos del usuario. CRUD directo, sin papelera: un movimiento
mal registrado se corrige o se borra. El cerebro no calcula balance ni
resumen — devuelve la lista y la app la corta por mes (ver
`features/finanzas` en la app). Mismo patrón que `categorias.py`.
"""
from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from ..db import Postgrest, get_db
from ..schemas.movimientos import (
    MovimientoCreate,
    MovimientoRead,
    MovimientoUpdate,
)
from ..security import require_api_key

router = APIRouter(
    prefix="/movimientos",
    tags=["movimientos"],
    dependencies=[Depends(require_api_key)],
)

TABLE = "movimientos"


@router.get("", response_model=list[MovimientoRead])
async def listar(db: Postgrest = Depends(get_db)) -> list[dict]:
    # Más recientes primero; la app corta por mes y arma el resumen.
    return await db.list(TABLE, order="fecha.desc")


@router.get("/{movimiento_id}", response_model=MovimientoRead)
async def obtener(movimiento_id: UUID, db: Postgrest = Depends(get_db)) -> dict:
    row = await db.get(TABLE, str(movimiento_id))
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Movimiento no encontrado",
        )
    return row


@router.post("", response_model=MovimientoRead, status_code=status.HTTP_201_CREATED)
async def crear(body: MovimientoCreate, db: Postgrest = Depends(get_db)) -> dict:
    # exclude_none: si `fecha` viene None, la deja fuera para que la BD
    # use su default (current_date).
    return await db.insert(TABLE, body.model_dump(mode="json", exclude_none=True))


@router.patch("/{movimiento_id}", response_model=MovimientoRead)
async def actualizar(
    movimiento_id: UUID,
    body: MovimientoUpdate,
    db: Postgrest = Depends(get_db),
) -> dict:
    payload = body.model_dump(mode="json", exclude_unset=True)
    row = await db.update(TABLE, str(movimiento_id), payload)
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Movimiento no encontrado",
        )
    return row


@router.delete("/{movimiento_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar(movimiento_id: UUID, db: Postgrest = Depends(get_db)) -> None:
    if not await db.delete(TABLE, str(movimiento_id)):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Movimiento no encontrado",
        )
