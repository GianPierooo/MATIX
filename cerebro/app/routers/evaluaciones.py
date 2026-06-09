"""CRUD de `evaluaciones` (Universidad).

2.0 · Fase 2: ENVOLTORIO DELGADO sobre los COMANDOS de
`app/comandos/universidad.py`. Crear/editar/borrar van por el comando (misma
ruta que la IA); los GET de lectura quedan directos (fila tipada para el hub)."""
from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from ..comandos import registro
from ..comandos.http import datos_o_http as _datos_o_http
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
    res = await registro.ejecutar(
        db, "crear_evaluacion", body.model_dump(mode="json", exclude_none=True), origen="ui"
    )
    return _datos_o_http(res)


@router.patch("/{evaluacion_id}", response_model=EvaluacionRead)
async def actualizar(
    evaluacion_id: UUID, body: EvaluacionUpdate, db: Postgrest = Depends(get_db)
) -> dict:
    params = {
        **body.model_dump(mode="json", exclude_unset=True),
        "evaluacion_id": str(evaluacion_id),
    }
    res = await registro.ejecutar(db, "editar_evaluacion", params, origen="ui")
    return _datos_o_http(res)


@router.delete("/{evaluacion_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar(evaluacion_id: UUID, db: Postgrest = Depends(get_db)) -> None:
    res = await registro.ejecutar(
        db, "eliminar_evaluacion", {"evaluacion_id": str(evaluacion_id)}, origen="ui"
    )
    _datos_o_http(res)
