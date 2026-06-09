"""CRUD de `cursos` (Universidad).

2.0 · Fase 2: este router es un ENVOLTORIO DELGADO sobre los COMANDOS de
`app/comandos/universidad.py`. La lógica de crear/editar/borrar vive UNA sola
vez ahí; las tools de la IA llaman al MISMO comando, así UI e IA hacen lo mismo
por una sola ruta. Los GET de lectura para la app quedan directos (devuelven la
fila tipada `CursoRead`, que es lo que el hub espera)."""
from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from ..comandos import registro
from ..comandos.http import datos_o_http as _datos_o_http
from ..db import Postgrest, get_db
from ..schemas.cursos import CursoCreate, CursoRead, CursoUpdate
from ..security import require_api_key

router = APIRouter(
    prefix="/cursos",
    tags=["cursos"],
    dependencies=[Depends(require_api_key)],
)

TABLE = "cursos"


@router.get("", response_model=list[CursoRead])
async def listar(db: Postgrest = Depends(get_db)) -> list[dict]:
    return await db.list(TABLE, order="nombre.asc")


@router.get("/{curso_id}", response_model=CursoRead)
async def obtener(curso_id: UUID, db: Postgrest = Depends(get_db)) -> dict:
    row = await db.get(TABLE, str(curso_id))
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Curso no encontrado")
    return row


@router.post("", response_model=CursoRead, status_code=status.HTTP_201_CREATED)
async def crear(body: CursoCreate, db: Postgrest = Depends(get_db)) -> dict:
    res = await registro.ejecutar(
        db, "crear_curso", body.model_dump(mode="json", exclude_none=True), origen="ui"
    )
    return _datos_o_http(res)


@router.patch("/{curso_id}", response_model=CursoRead)
async def actualizar(curso_id: UUID, body: CursoUpdate, db: Postgrest = Depends(get_db)) -> dict:
    params = {**body.model_dump(mode="json", exclude_unset=True), "curso_id": str(curso_id)}
    res = await registro.ejecutar(db, "editar_curso", params, origen="ui")
    return _datos_o_http(res)


@router.delete("/{curso_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar(curso_id: UUID, db: Postgrest = Depends(get_db)) -> None:
    res = await registro.ejecutar(db, "eliminar_curso", {"curso_id": str(curso_id)}, origen="ui")
    _datos_o_http(res)  # levanta 404 si no existe; ignora el body en 204
