"""Router del PLAN DEL DÍA (capa de horario) para la vista «Hoy» de la app.

Expone vía REST lo que `app.matix.horario` ya calcula (hasta ahora solo estaba
como tool de chat): el plan colocado en las ventanas libres, el replan desde la
hora actual, las acciones del loop (hecho/saltado) y el empuje al calendario.
Reusa la creación de eventos existente (no duplica).
"""
from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends

from ..db import Postgrest, get_db
from ..matix import horario
from ..schemas.horario import (
    CompletarBloqueRequest,
    PlanDelDiaRead,
    PushCalendarioRequest,
    ReplanRequest,
    SaltarBloqueRequest,
)
from ..security import require_api_key

router = APIRouter(
    prefix="/horario",
    tags=["horario"],
    dependencies=[Depends(require_api_key)],
)


@router.get("", response_model=PlanDelDiaRead)
async def plan_de_hoy(db: Postgrest = Depends(get_db)) -> dict:
    """Plan del día colocado en las ventanas libres reales. Determinístico: se
    recalcula al vuelo desde el estado actual (set, tareas, fijos, anclas)."""
    return await horario.plan_de_hoy_data(db)


@router.post("/replanificar", response_model=PlanDelDiaRead)
async def replanificar(
    body: ReplanRequest | None = None, db: Postgrest = Depends(get_db)
) -> dict:
    """Replanifica el RESTO del día desde la hora actual (corre/suelta por
    prioridad lo pendiente, respeta lo fijo)."""
    ahora = (body.ahora if body else None) or datetime.now(timezone.utc)
    return await horario.plan_de_hoy_data(db, ahora=ahora, desde_ahora=True)


@router.post("/despertar")
async def despertar(db: Postgrest = Depends(get_db)) -> dict:
    """Botón "Me acabo de levantar": registra el ancla de despertar de HOY
    (sin tocar la rutina estándar), materializa el set del día y devuelve el
    plan recalculado desde esta hora. 100% DETERMINISTA (sin LLM): las cosas de
    hoy aparecen al instante. Devuelve `{despierta_hoy, plan}`."""
    return await horario.marcar_despertar(db, ahora=datetime.now(timezone.utc))


@router.post("/bloque/completar")
async def completar_bloque(
    body: CompletarBloqueRequest, db: Postgrest = Depends(get_db)
) -> dict:
    """Marca un bloque planificado como hecho (cierra nodo y/o tarea)."""
    return await horario.completar_bloque(
        db,
        tarea_id=str(body.tarea_id) if body.tarea_id else None,
        nodo_id=str(body.nodo_id) if body.nodo_id else None,
    )


@router.post("/bloque/saltar")
async def saltar_bloque(
    body: SaltarBloqueRequest, db: Postgrest = Depends(get_db)
) -> dict:
    """Salta un bloque del set (no hoy, sin culpa)."""
    return await horario.saltar_bloque(db, set_item_id=str(body.set_item_id))


@router.post("/calendario")
async def empujar_a_calendario(
    body: PushCalendarioRequest | None = None, db: Postgrest = Depends(get_db)
) -> dict:
    """Crea los bloques planificados como eventos tentativos. Idempotente: no
    duplica si ya se empujó (mismo título + hora de inicio hoy). Si la app manda
    `bloques` (con sus horas editadas), usa esos."""
    bloques = (
        [b.model_dump() for b in body.bloques]
        if body and body.bloques is not None
        else None
    )
    return await horario.empujar_a_calendario(db, bloques=bloques)
