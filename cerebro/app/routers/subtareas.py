from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status

from ..db import Postgrest, get_db
from ..schemas.subtareas import SubtareaCreate, SubtareaRead, SubtareaUpdate
from ..security import require_api_key

router = APIRouter(
    prefix="/subtareas",
    tags=["subtareas"],
    dependencies=[Depends(require_api_key)],
)

TABLE = "subtareas"


@router.get("", response_model=list[SubtareaRead])
async def listar(
    tarea_id: UUID | None = Query(default=None),
    db: Postgrest = Depends(get_db),
) -> list[dict]:
    """Lista subtareas. Si se pasa `?tarea_id=...`, devuelve solo las
    de esa tarea. Sin filtro, devuelve todas (útil para mantenimiento
    o herramientas, no para la app — el cliente debe filtrar por
    tarea para no bajarse toda la tabla)."""
    return await db.list(
        TABLE,
        order="orden.asc",
        filters={"tarea_id": str(tarea_id)} if tarea_id else None,
    )


@router.get("/{subtarea_id}", response_model=SubtareaRead)
async def obtener(subtarea_id: UUID, db: Postgrest = Depends(get_db)) -> dict:
    row = await db.get(TABLE, str(subtarea_id))
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Subtarea no encontrada")
    return row


@router.post("", response_model=SubtareaRead, status_code=status.HTTP_201_CREATED)
async def crear(body: SubtareaCreate, db: Postgrest = Depends(get_db)) -> dict:
    return await db.insert(TABLE, body.model_dump(mode="json", exclude_none=True))


@router.patch("/{subtarea_id}", response_model=SubtareaRead)
async def actualizar(
    subtarea_id: UUID, body: SubtareaUpdate, db: Postgrest = Depends(get_db)
) -> dict:
    payload = body.model_dump(mode="json", exclude_unset=True)
    row = await db.update(TABLE, str(subtarea_id), payload)
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Subtarea no encontrada")
    return row


@router.delete("/{subtarea_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar(subtarea_id: UUID, db: Postgrest = Depends(get_db)) -> None:
    if not await db.delete(TABLE, str(subtarea_id)):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Subtarea no encontrada")
