"""Router CRUD de `tracks` de aprendizaje (Fase 2).

Reglas:

- **Tope de 3 activos**: crear o reactivar un track que dejaría más de 3
  con estado `activo` devuelve 409. La regla vive aquí (no en la BD) para
  dar un mensaje legible. Igual que los proyectos.
- Los tracks son CONTINUOS: solo `activo` / `pausado` (no se terminan).
- Fijar posición = editar `bloque_actual` / `semana` / `dia`.
"""
from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from ..db import Postgrest, get_db
from ..schemas.tracks import TrackCreate, TrackRead, TrackUpdate
from ..security import require_api_key

router = APIRouter(
    prefix="/tracks",
    tags=["tracks"],
    dependencies=[Depends(require_api_key)],
)

TABLE = "tracks"
TOPE_ACTIVOS = 3
MSG_TOPE = (
    f"Ya tienes {TOPE_ACTIVOS} tracks activos: pausa uno primero."
)


async def _contar_activos(db: Postgrest, *, excluir_id: str | None = None) -> int:
    activos = await db.list(TABLE, filters={"estado": "activo"})
    if excluir_id:
        activos = [t for t in activos if t["id"] != excluir_id]
    return len(activos)


@router.get("", response_model=list[TrackRead])
async def listar_tracks(db: Postgrest = Depends(get_db)) -> list[dict]:
    # Activos primero, luego por creación reciente.
    return await db.list(TABLE, order="estado.asc,creado_en.desc")


@router.get("/{track_id}", response_model=TrackRead)
async def obtener_track(track_id: UUID, db: Postgrest = Depends(get_db)) -> dict:
    row = await db.get(TABLE, str(track_id))
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Track no encontrado"
        )
    return row


@router.post("", response_model=TrackRead, status_code=status.HTTP_201_CREATED)
async def crear_track(
    body: TrackCreate, db: Postgrest = Depends(get_db)
) -> dict:
    payload = body.model_dump(mode="json", exclude_none=True)
    if (
        payload.get("estado", "activo") == "activo"
        and await _contar_activos(db) >= TOPE_ACTIVOS
    ):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail=MSG_TOPE
        )
    return await db.insert(TABLE, payload)


@router.patch("/{track_id}", response_model=TrackRead)
async def actualizar_track(
    track_id: UUID, body: TrackUpdate, db: Postgrest = Depends(get_db)
) -> dict:
    actual = await db.get(TABLE, str(track_id))
    if actual is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Track no encontrado"
        )

    payload = body.model_dump(mode="json", exclude_unset=True)

    nuevo_estado = payload.get("estado")
    if (
        nuevo_estado == "activo"
        and actual["estado"] != "activo"
        and await _contar_activos(db, excluir_id=str(track_id)) >= TOPE_ACTIVOS
    ):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail=MSG_TOPE
        )

    row = await db.update(TABLE, str(track_id), payload)
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Track no encontrado"
        )
    return row


@router.delete("/{track_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar_track(
    track_id: UUID, db: Postgrest = Depends(get_db)
) -> None:
    ok = await db.delete(TABLE, str(track_id))
    if not ok:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Track no encontrado"
        )
