"""CRUD de `sesiones_clase` (Universidad — el horario semanal).

2.0 · Fase 2: ENVOLTORIO DELGADO sobre los COMANDOS de
`app/comandos/universidad.py`. Crear/editar/borrar van por el comando (misma
ruta que la IA); los GET de lectura quedan directos (fila tipada para el hub).

La recurrencia de una clase ("lunes y miércoles") se modela como N filas, una
por día — no usa la recurrencia general de eventos (G5). El comando
`crear_sesiones_clase` materializa eso desde la IA; la app crea una por POST."""
from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from ..comandos import registro
from ..comandos.http import datos_o_http as _datos_o_http
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
    res = await registro.ejecutar(
        db, "crear_sesion_clase", body.model_dump(mode="json", exclude_none=True), origen="ui"
    )
    return _datos_o_http(res)


@router.patch("/{sesion_id}", response_model=SesionClaseRead)
async def actualizar(
    sesion_id: UUID, body: SesionClaseUpdate, db: Postgrest = Depends(get_db)
) -> dict:
    params = {**body.model_dump(mode="json", exclude_unset=True), "sesion_id": str(sesion_id)}
    res = await registro.ejecutar(db, "editar_sesion_clase", params, origen="ui")
    return _datos_o_http(res)


@router.delete("/{sesion_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar(sesion_id: UUID, db: Postgrest = Depends(get_db)) -> None:
    res = await registro.ejecutar(
        db, "eliminar_sesion_clase", {"sesion_id": str(sesion_id)}, origen="ui"
    )
    _datos_o_http(res)
