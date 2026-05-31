"""Modos de Matix (tono + conocimiento + prioridades).

- `GET /modos` — lista los modos disponibles (de los `.md` del repo) y cuál
  está activo.
- `POST /modos/activar` — activa un modo (lo mismo que la tool `activar_modo`,
  pero desde la UI del chat).
- `POST /modos/desactivar` — vuelve al modo normal.

El modo activo se persiste en `config_matix`; el chat lo inyecta como
contenido system adicional.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status

from ..db import Postgrest, get_db
from ..matix import modos as modos_mod
from ..schemas.modos import ActivarModoRequest, ModosEstado
from ..security import require_api_key

router = APIRouter(
    prefix="/modos",
    tags=["modos"],
    dependencies=[Depends(require_api_key)],
)


async def _estado(db: Postgrest, activo: str | None) -> dict:
    return {"disponibles": modos_mod.listar_modos(), "activo": activo}


@router.get("", response_model=ModosEstado)
async def estado(db: Postgrest = Depends(get_db)) -> dict:
    return await _estado(db, await modos_mod.modo_activo(db))


@router.post("/activar", response_model=ModosEstado)
async def activar(
    body: ActivarModoRequest, db: Postgrest = Depends(get_db)
) -> dict:
    nombre = body.modo.strip().lower()
    if not modos_mod.existe_modo(nombre):
        disp = ", ".join(m["nombre"] for m in modos_mod.listar_modos())
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Modo desconocido: «{body.modo}». Los modos son: {disp}.",
        )
    await modos_mod.set_modo_activo(db, nombre)
    return await _estado(db, nombre)


@router.post("/desactivar", response_model=ModosEstado)
async def desactivar(db: Postgrest = Depends(get_db)) -> dict:
    await modos_mod.set_modo_activo(db, None)
    return await _estado(db, None)
