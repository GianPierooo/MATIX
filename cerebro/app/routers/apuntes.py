"""CRUD de `apuntes` con borrado suave (Capa 2 Paso 5).

Ver `routers/tareas.py` para el modelo conceptual: DELETE manda al
papelera, `/restaurar` lo recupera, `/permanente` destruye.
"""
from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status

from ..db import Postgrest, get_db
from ..schemas.apuntes import ApunteCreate, ApunteRead, ApunteUpdate
from ..security import require_api_key

router = APIRouter(
    prefix="/apuntes",
    tags=["apuntes"],
    dependencies=[Depends(require_api_key)],
)

TABLE = "apuntes"


def _ahora_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


@router.get("", response_model=list[ApunteRead])
async def listar(
    papelera: bool = Query(default=False),
    db: Postgrest = Depends(get_db),
) -> list[dict]:
    raw_filters = {
        "eliminado_en": "not.is.null" if papelera else "is.null",
    }
    return await db.list(
        TABLE, order="actualizado_en.desc", raw_filters=raw_filters
    )


@router.get("/{apunte_id}", response_model=ApunteRead)
async def obtener(apunte_id: UUID, db: Postgrest = Depends(get_db)) -> dict:
    row = await db.get(TABLE, str(apunte_id))
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Apunte no encontrado"
        )
    return row


@router.post("", response_model=ApunteRead, status_code=status.HTTP_201_CREATED)
async def crear(body: ApunteCreate, db: Postgrest = Depends(get_db)) -> dict:
    return await db.insert(TABLE, body.model_dump(mode="json", exclude_none=True))


@router.patch("/{apunte_id}", response_model=ApunteRead)
async def actualizar(
    apunte_id: UUID, body: ApunteUpdate, db: Postgrest = Depends(get_db)
) -> dict:
    payload = body.model_dump(mode="json", exclude_unset=True)
    row = await db.update(TABLE, str(apunte_id), payload)
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Apunte no encontrado"
        )
    return row


@router.delete("/{apunte_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar(apunte_id: UUID, db: Postgrest = Depends(get_db)) -> None:
    """Borrado suave."""
    row = await db.update(
        TABLE, str(apunte_id), {"eliminado_en": _ahora_iso()}
    )
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Apunte no encontrado"
        )


@router.post("/{apunte_id}/restaurar", response_model=ApunteRead)
async def restaurar(
    apunte_id: UUID, db: Postgrest = Depends(get_db)
) -> dict:
    row = await db.update(TABLE, str(apunte_id), {"eliminado_en": None})
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Apunte no encontrado"
        )
    return row


@router.delete(
    "/{apunte_id}/permanente", status_code=status.HTTP_204_NO_CONTENT
)
async def eliminar_permanente(
    apunte_id: UUID, db: Postgrest = Depends(get_db)
) -> None:
    ok = await db.delete(TABLE, str(apunte_id))
    if not ok:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Apunte no encontrado"
        )
