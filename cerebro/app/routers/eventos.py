"""CRUD de `eventos` con borrado suave (Capa 2 Paso 5).

Ver `routers/tareas.py` para el modelo conceptual: DELETE manda al
papelera, `/restaurar` lo recupera, `/permanente` destruye.
"""
from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status

from ..db import Postgrest, get_db
from ..schemas.eventos import EventoCreate, EventoRead, EventoUpdate
from ..security import require_api_key

router = APIRouter(
    prefix="/eventos",
    tags=["eventos"],
    dependencies=[Depends(require_api_key)],
)

TABLE = "eventos"


def _ahora_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


@router.get("", response_model=list[EventoRead])
async def listar(
    papelera: bool = Query(default=False),
    db: Postgrest = Depends(get_db),
) -> list[dict]:
    raw_filters = {
        "eliminado_en": "not.is.null" if papelera else "is.null",
    }
    return await db.list(
        TABLE, order="inicia_en.asc", raw_filters=raw_filters
    )


@router.get("/{evento_id}", response_model=EventoRead)
async def obtener(evento_id: UUID, db: Postgrest = Depends(get_db)) -> dict:
    row = await db.get(TABLE, str(evento_id))
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Evento no encontrado"
        )
    return row


@router.post("", response_model=EventoRead, status_code=status.HTTP_201_CREATED)
async def crear(body: EventoCreate, db: Postgrest = Depends(get_db)) -> dict:
    return await db.insert(TABLE, body.model_dump(mode="json", exclude_none=True))


@router.patch("/{evento_id}", response_model=EventoRead)
async def actualizar(
    evento_id: UUID, body: EventoUpdate, db: Postgrest = Depends(get_db)
) -> dict:
    payload = body.model_dump(mode="json", exclude_unset=True)
    row = await db.update(TABLE, str(evento_id), payload)
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Evento no encontrado"
        )
    return row


@router.delete("/{evento_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar(evento_id: UUID, db: Postgrest = Depends(get_db)) -> None:
    """Borrado suave."""
    row = await db.update(
        TABLE, str(evento_id), {"eliminado_en": _ahora_iso()}
    )
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Evento no encontrado"
        )


@router.post("/{evento_id}/restaurar", response_model=EventoRead)
async def restaurar(
    evento_id: UUID, db: Postgrest = Depends(get_db)
) -> dict:
    row = await db.update(TABLE, str(evento_id), {"eliminado_en": None})
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Evento no encontrado"
        )
    return row


@router.delete(
    "/{evento_id}/permanente", status_code=status.HTTP_204_NO_CONTENT
)
async def eliminar_permanente(
    evento_id: UUID, db: Postgrest = Depends(get_db)
) -> None:
    ok = await db.delete(TABLE, str(evento_id))
    if not ok:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Evento no encontrado"
        )
