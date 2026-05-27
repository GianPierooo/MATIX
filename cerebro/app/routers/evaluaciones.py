from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from ..db import Postgrest, get_db
from ..schemas.evaluaciones import (
    EvaluacionCreate,
    EvaluacionRead,
    EvaluacionUpdate,
)
from ..security import require_api_key

router = APIRouter(
    prefix="/evaluaciones",
    tags=["evaluaciones"],
    dependencies=[Depends(require_api_key)],
)

TABLE = "evaluaciones"


@router.get("", response_model=list[EvaluacionRead])
async def listar(db: Postgrest = Depends(get_db)) -> list[dict]:
    return await db.list(TABLE, order="fecha.asc")


@router.get("/{evaluacion_id}", response_model=EvaluacionRead)
async def obtener(evaluacion_id: UUID, db: Postgrest = Depends(get_db)) -> dict:
    row = await db.get(TABLE, str(evaluacion_id))
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Evaluación no encontrada"
        )
    return row


@router.post("", response_model=EvaluacionRead, status_code=status.HTTP_201_CREATED)
async def crear(body: EvaluacionCreate, db: Postgrest = Depends(get_db)) -> dict:
    return await db.insert(TABLE, body.model_dump(mode="json", exclude_none=True))


@router.patch("/{evaluacion_id}", response_model=EvaluacionRead)
async def actualizar(
    evaluacion_id: UUID, body: EvaluacionUpdate, db: Postgrest = Depends(get_db)
) -> dict:
    payload = body.model_dump(mode="json", exclude_unset=True)
    row = await db.update(TABLE, str(evaluacion_id), payload)
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Evaluación no encontrada"
        )
    return row


@router.delete("/{evaluacion_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar(evaluacion_id: UUID, db: Postgrest = Depends(get_db)) -> None:
    if not await db.delete(TABLE, str(evaluacion_id)):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Evaluación no encontrada"
        )
