"""Router de proactividad (Capa 8).

Endpoints:

- `GET /api/v1/briefing/hoy` — briefing matutino del día (Paso 1).
- `GET /api/v1/briefing/cierre` — cierre del día (Paso 2).

Ambos arman contenido a demanda leyendo el hub; no hay programación
del lado servidor — la entrega es una notificación local que la app
programa con `flutter_local_notifications` (ver `docs/Plan_Capa8.md`
· Decisión 1). La app consume estos endpoints al tocar la
notificación o desde Ajustes.
"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends

from ..briefing import armar as briefing_armar
from ..briefing import cierre as briefing_cierre
from ..briefing import repaso_semanal
from ..db import Postgrest, get_db
from ..schemas.briefing import (
    BriefingHoyRead,
    CierreHoyRead,
    RepasoSemanalRead,
)
from ..security import require_api_key

router = APIRouter(
    prefix="/briefing",
    tags=["briefing"],
    dependencies=[Depends(require_api_key)],
)


@router.get("/hoy", response_model=BriefingHoyRead)
async def briefing_de_hoy(
    db: Postgrest = Depends(get_db),
) -> dict[str, Any]:
    return await briefing_armar.armar_briefing(db)


@router.get("/cierre", response_model=CierreHoyRead)
async def cierre_de_hoy(
    db: Postgrest = Depends(get_db),
) -> dict[str, Any]:
    return await briefing_cierre.armar_cierre(db)


@router.get("/repaso-semanal", response_model=RepasoSemanalRead)
async def repaso_de_la_semana(
    db: Postgrest = Depends(get_db),
) -> dict[str, Any]:
    """Repaso semanal on-demand (Capa 8 · Repaso). Matix sintetiza la
    semana del hub. Nunca falla: si el LLM no está, cae a un resumen
    determinístico."""
    return await repaso_semanal.armar_repaso(db)
