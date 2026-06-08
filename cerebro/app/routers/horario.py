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
from ..matix import horario, notis_programadas
from ..schemas.horario import (
    CompletarBloqueRequest,
    PlanDelDiaRead,
    AgendarRequest,
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


@router.get("/notis-programadas")
async def listar_notis_programadas(db: Postgrest = Depends(get_db)) -> dict:
    """Lista las notis que la app debe meter al scheduler local para el resto
    de HOY (Lima): resumen matutino + pre-actividad por cada bloque + nudges
    del próximo bloque dosificados por el dial de intensidad. 100% determinista
    (plantilla + plan); cero LLM, cero tokens. Respeta quiet hours.

    La app cancela las anteriores del día por `dedup_key` y reprograma — re-
    pedir no duplica. Las notis sobreviven al background porque las dispara el
    AlarmManager del sistema (no la app), bien para MagicOS.
    """
    ahora = datetime.now(timezone.utc)
    plan = await horario.plan_de_hoy_data(db, ahora=ahora)
    cfgs = await db.list("config_nudges", limit=1)
    cfg = cfgs[0] if cfgs else None
    notis = notis_programadas.armar_notis_programadas(plan, cfg, ahora=ahora)
    return {
        "ahora": ahora.isoformat(),
        "fecha": plan.get("fecha"),
        "intensidad": (cfg or {}).get("intensidad", "intenso"),
        "lead_pre_actividad_min": (cfg or {}).get("pre_actividad_min")
            or notis_programadas.LEAD_DEFAULT_MIN,
        "notis": [n.to_dict() for n in notis],
    }


@router.post("/agendar")
async def agendar(
    body: AgendarRequest | None = None, db: Postgrest = Depends(get_db)
) -> dict:
    """Agenda los bloques tentativos del plan como TAREAS del hub (camino único
    canónico de "agregar al día"). Cada bloque engancha su tarea (existente o
    nueva) a su horario; NUNCA crea eventos pelados. Así aparece en Tareas y en
    Tu día. Idempotente. Si la app manda `bloques` (con sus ediciones), usa esos."""
    bloques = (
        [b.model_dump() for b in body.bloques]
        if body and body.bloques is not None
        else None
    )
    return await horario.agendar_plan(db, bloques=bloques)
