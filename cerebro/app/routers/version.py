"""Endpoint de auto-actualización in-app.

La app, al iniciar, hace `GET /api/v1/version` y compara su
`buildNumber` local contra el de la respuesta. Si el del servidor
es mayor, ofrece descargar e instalar.

Decisiones:

- Requiere `X-Matix-Key` como el resto del API. La app la tiene
  embebida y la usa para todo; no abrimos un canal sin auth solo
  para este chequeo.
- Si todavía no hay ninguna versión publicada (recién creada la
  tabla), devolvemos `{"disponible": false}` con 200. La app lo
  trata como "no hay update". No es un error.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends

from ..db import Postgrest, get_db
from ..security import require_api_key

router = APIRouter(
    prefix="/version",
    tags=["version"],
    dependencies=[Depends(require_api_key)],
)


@router.get("")
async def ultima_version(db: Postgrest = Depends(get_db)) -> dict:
    filas = await db.list(
        "app_versions",
        order="build_number.desc",
        limit=1,
    )
    if not filas:
        # Sin ninguna versión publicada todavía. La app lo lee como
        # "no hay update disponible" y sigue normal.
        return {"disponible": False}
    f = filas[0]
    return {
        "disponible": True,
        "version": f["version"],
        "build_number": f["build_number"],
        "apk_url": f["apk_url"],
        "notas": f.get("notas", ""),
        "sha": f.get("sha"),
        "creado_en": f["creado_en"],
    }
