from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from ..db import Postgrest, get_db
from ..schemas.profile import ProfileCreate, ProfileRead, ProfileUpdate
from ..security import require_api_key

router = APIRouter(
    prefix="/profile",
    tags=["profile"],
    dependencies=[Depends(require_api_key)],
)

TABLE = "profile"


@router.get("", response_model=list[ProfileRead])
async def listar_profile(db: Postgrest = Depends(get_db)) -> list[dict]:
    return await db.list(TABLE, order="creado_en.desc")


@router.get("/{profile_id}", response_model=ProfileRead)
async def obtener_profile(profile_id: UUID, db: Postgrest = Depends(get_db)) -> dict:
    row = await db.get(TABLE, str(profile_id))
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Profile no encontrado")
    return row


@router.post("", response_model=ProfileRead, status_code=status.HTTP_201_CREATED)
async def crear_profile(body: ProfileCreate, db: Postgrest = Depends(get_db)) -> dict:
    return await db.insert(TABLE, body.model_dump(mode="json", exclude_none=True))


@router.patch("/{profile_id}", response_model=ProfileRead)
async def actualizar_profile(
    profile_id: UUID, body: ProfileUpdate, db: Postgrest = Depends(get_db)
) -> dict:
    payload = body.model_dump(mode="json", exclude_unset=True)
    row = await db.update(TABLE, str(profile_id), payload)
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Profile no encontrado")
    return row


@router.delete("/{profile_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar_profile(profile_id: UUID, db: Postgrest = Depends(get_db)) -> None:
    if not await db.delete(TABLE, str(profile_id)):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Profile no encontrado")
