"""Memoria personal de Matix (pantalla 'Sobre mí').

CRUD de los hechos que Matix sabe del usuario. Control total del usuario:
ver, agregar, editar y borrar. Las mismas operaciones que Matix hace por
tools (recordar/actualizar_memoria/olvidar), pero desde la app.

El embedding (RAG) se regenera best-effort al crear/editar, igual que en el
flujo de Matix.
"""
from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from ..db import Postgrest, get_db
from ..matix import memoria as memoria_mod
from ..schemas.memoria import MemoriaCreate, MemoriaRead, MemoriaUpdate
from ..security import require_api_key

router = APIRouter(
    prefix="/memoria",
    tags=["memoria"],
    dependencies=[Depends(require_api_key)],
)


@router.get("", response_model=list[MemoriaRead])
async def listar(db: Postgrest = Depends(get_db)) -> list[dict]:
    return await memoria_mod.listar(db)


@router.post("", response_model=MemoriaRead, status_code=status.HTTP_201_CREATED)
async def crear(body: MemoriaCreate, db: Postgrest = Depends(get_db)) -> dict:
    return await memoria_mod.recordar(
        db,
        contenido=body.contenido,
        categoria=body.categoria,
        esencial=body.esencial,
    )


@router.patch("/{memoria_id}", response_model=MemoriaRead)
async def actualizar(
    memoria_id: UUID, body: MemoriaUpdate, db: Postgrest = Depends(get_db)
) -> dict:
    fila = await memoria_mod.actualizar(
        db,
        memoria_id=str(memoria_id),
        contenido=body.contenido,
        categoria=body.categoria,
        esencial=body.esencial,
    )
    if fila is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ese recuerdo no existe.",
        )
    return fila


@router.delete("/{memoria_id}", status_code=status.HTTP_204_NO_CONTENT)
async def borrar(memoria_id: UUID, db: Postgrest = Depends(get_db)) -> None:
    ok = await memoria_mod.olvidar(db, memoria_id=str(memoria_id))
    if not ok:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ese recuerdo no existe.",
        )
