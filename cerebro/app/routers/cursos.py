from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

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
    return await db.insert(TABLE, body.model_dump(mode="json", exclude_none=True))


@router.patch("/{curso_id}", response_model=CursoRead)
async def actualizar(curso_id: UUID, body: CursoUpdate, db: Postgrest = Depends(get_db)) -> dict:
    payload = body.model_dump(mode="json", exclude_unset=True)
    row = await db.update(TABLE, str(curso_id), payload)
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Curso no encontrado")
    return row


@router.delete("/{curso_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar(curso_id: UUID, db: Postgrest = Depends(get_db)) -> None:
    if not await db.delete(TABLE, str(curso_id)):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Curso no encontrado")
