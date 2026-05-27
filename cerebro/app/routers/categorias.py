from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from ..db import Postgrest, get_db
from ..schemas.categorias import CategoriaCreate, CategoriaRead, CategoriaUpdate
from ..security import require_api_key

router = APIRouter(
    prefix="/categorias",
    tags=["categorias"],
    dependencies=[Depends(require_api_key)],
)

TABLE = "categorias"


@router.get("", response_model=list[CategoriaRead])
async def listar(db: Postgrest = Depends(get_db)) -> list[dict]:
    return await db.list(TABLE, order="nombre.asc")


@router.get("/{categoria_id}", response_model=CategoriaRead)
async def obtener(categoria_id: UUID, db: Postgrest = Depends(get_db)) -> dict:
    row = await db.get(TABLE, str(categoria_id))
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Categoría no encontrada")
    return row


@router.post("", response_model=CategoriaRead, status_code=status.HTTP_201_CREATED)
async def crear(body: CategoriaCreate, db: Postgrest = Depends(get_db)) -> dict:
    return await db.insert(TABLE, body.model_dump(mode="json", exclude_none=True))


@router.patch("/{categoria_id}", response_model=CategoriaRead)
async def actualizar(
    categoria_id: UUID, body: CategoriaUpdate, db: Postgrest = Depends(get_db)
) -> dict:
    payload = body.model_dump(mode="json", exclude_unset=True)
    row = await db.update(TABLE, str(categoria_id), payload)
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Categoría no encontrada")
    return row


@router.delete("/{categoria_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar(categoria_id: UUID, db: Postgrest = Depends(get_db)) -> None:
    if not await db.delete(TABLE, str(categoria_id)):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Categoría no encontrada")
