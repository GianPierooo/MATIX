"""Comandos del PLANIFICADOR / "Tu día" (2.0 · Fase 5).

El subsistema más interconectado: set del día, plan en ventanas, rollover de lo
no cumplido, despertar y las acciones de bloque. Sigue el patrón de Fases 1-4:
cada acción del bucle diario es UN comando; el endpoint de la app, el robot y la
tool de la IA invocan el MISMO handler.

DETERMINISMO (no negociable): estos comandos son ENVOLTORIOS DELGADOS sobre las
funciones deterministas que YA existen en `matix.horario`,
`matix.planificador_diario` y `matix.rollover`. NO se reescribe el cálculo del
plan, el rollover, las ventanas libres, las sugerencias ni el rundown del
despertar — siguen siendo puros/deterministas, sin LLM. La IA SOLO elige qué
comando llamar; el trabajo del comando NUNCA pasa por el modelo. Este módulo, a
propósito, no importa `llm` ni nada que llame al modelo (los módulos `matix` se
importan PEREZOSAMENTE dentro de cada handler, igual que en `tareas.py`).

D3 consolidado: "meter algo al plan del día" tiene una sola ruta canónica vía
`agendar_bloque` (envuelve `horario.agendar_plan`, que a su vez ya delega en
`planificador_diario.aceptar_items` para los items del set — la unificación a
nivel de datos ya existía; aquí se unifica a nivel de comando: UI e IA entran
por el mismo handler).

D5 / Fase 4 reconciliado: `completar_bloque` envuelve `horario.completar_bloque`,
que ya enruta a los comandos canónicos `completar_tarea` (Fase 1) y
`completar_avance_proyecto` (Fase 4) — mismo estado, mismo %, desde donde sea.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from ..db import Postgrest
from .registro import Comando, RegistroComandos, Riesgo, error, ok


def _ahora() -> datetime:
    return datetime.now(timezone.utc)


# ── Set del día ───────────────────────────────────────────────────────────────


async def cmd_proponer_set_dia(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    """Materializa el set PROPUESTO del día (determinista: árbol + ritmo real)."""
    from ..matix import planificador_diario

    items = await planificador_diario.construir_set(db)
    return ok({"items": items, "total": len(items)})


async def cmd_ver_set_dia(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    from ..matix import planificador_diario

    hoy = _ahora().astimezone(planificador_diario.LIMA).date().isoformat()
    items = await db.list("set_diario_items", filters={"fecha": hoy}, order="orden.asc")
    return ok({"items": items, "total": len(items)})


async def cmd_aceptar_set_dia(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    """Promueve items del set a Tareas del hub (ruta del set; misma base que
    `agendar_bloque` usa para los items del set — D3)."""
    from ..matix import planificador_diario

    ids = params.get("item_ids")
    item_ids = [str(x) for x in ids] if isinstance(ids, list) and ids else None
    promovidos = await planificador_diario.aceptar_items(db, item_ids=item_ids)
    return ok({"aceptadas": len(promovidos), "items": promovidos})


async def cmd_saltar_item_set(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    item_id = (params.get("item_id") or "").strip()
    if not item_id:
        return error("validacion", "Pásame el `item_id` a saltar (lo ves en el set).")
    fila = await db.update("set_diario_items", item_id, {"estado": "saltado"})
    if fila is None:
        return error("no_existe", "No encontré ese item del set.")
    return ok({"item_id": item_id, "saltada": True})


# ── Bloques del plan del día ─────────────────────────────────────────────────


async def cmd_agendar_bloque(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    """Ruta canónica de "agregar al día" (D3). Engancha cada bloque a su tarea
    (existente o nueva) y a su horario; NUNCA crea eventos pelados. Sin `bloques`,
    agenda el plan calculado al vuelo. Editar la hora de un bloque = re-agendar
    su tarea con el nuevo `inicio`/`fin`."""
    from ..matix import horario

    bloques = params.get("bloques")
    if bloques is not None and not isinstance(bloques, list):
        return error("validacion", "`bloques` debe ser una lista.")
    res = await horario.agendar_plan(db, bloques=bloques)
    return ok(res)


async def cmd_saltar_bloque(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    from ..matix import horario

    set_item_id = (params.get("set_item_id") or "").strip()
    if not set_item_id:
        return error("validacion", "Pásame el `set_item_id` del bloque a saltar.")
    res = await horario.saltar_bloque(db, set_item_id=set_item_id)
    return ok(res)


async def cmd_completar_bloque(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    """Completa un bloque agendado. Enruta (vía horario.completar_bloque) a los
    comandos canónicos `completar_tarea` (Fase 1) y `completar_avance_proyecto`
    (Fase 4): mismo estado, mismo %, desde donde sea (D5)."""
    from ..matix import horario

    tarea_id = params.get("tarea_id")
    nodo_id = params.get("nodo_id")
    if not tarea_id and not nodo_id:
        return error("validacion", "Pásame `tarea_id` y/o `nodo_id` del bloque a completar.")
    res = await horario.completar_bloque(
        db,
        tarea_id=str(tarea_id) if tarea_id else None,
        nodo_id=str(nodo_id) if nodo_id else None,
    )
    return ok(res)


# ── Plan / replan / despertar ────────────────────────────────────────────────


async def cmd_plan_de_hoy(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    """Plan del día colocado en las ventanas libres. Solo lectura (se calcula al
    vuelo, determinista)."""
    from ..matix import horario

    desde_ahora = bool(params.get("desde_ahora"))
    data = await horario.plan_de_hoy_data(db, desde_ahora=desde_ahora)
    return ok(data)


async def cmd_replanificar_dia(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    """Replanifica el RESTO del día desde la hora actual. Solo lectura. Acepta un
    `ahora` ISO opcional (el endpoint /horario/replanificar lo expone para
    pruebas / replan a una hora dada); sin él, usa la hora del servidor."""
    from ..matix import horario

    ahora = _ahora()
    raw = params.get("ahora")
    if raw:
        try:
            ahora = raw if isinstance(raw, datetime) else datetime.fromisoformat(str(raw))
        except (ValueError, TypeError):
            return error("validacion", "`ahora` debe ser un timestamp ISO 8601.")
    data = await horario.plan_de_hoy_data(db, ahora=ahora, desde_ahora=True)
    return ok(data)


async def cmd_marcar_despertar(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    """"Me acabo de levantar": ancla de despertar de hoy + rundown determinista
    del día (set materializado + plan desde esta hora). Sin LLM."""
    from ..matix import horario

    res = await horario.marcar_despertar(db, ahora=_ahora())
    return ok(res)


# ── Rollover de lo no cumplido ───────────────────────────────────────────────


async def cmd_proponer_rollover(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    """Propuestas (deterministas) de reprogramación de lo no cumplido + flag de
    sobrecarga. Solo lectura: no mueve nada hasta que el usuario decida."""
    from ..matix import rollover

    res = await rollover.proponer_rollover(db, ahora=_ahora(), hasta_fin_de_hoy=True)
    return ok(res)


# Decisiones aceptadas por el rollover. "posponer" es el nombre humano de
# "otro_dia" (postergar al siguiente día con hueco).
_DECISIONES = {"aceptar", "otro_dia", "soltar", "posponer"}


async def cmd_aplicar_rollover(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    """Aplica la decisión sobre una tarea no cumplida: aceptar (mueve al
    siguiente hueco) / otro_dia | posponer (salta hoy) / soltar (a la papelera).
    Determinista: la colocación la calcula el motor de huecos, sin LLM."""
    from ..matix import rollover

    tarea_id = (params.get("tarea_id") or "").strip()
    if not tarea_id:
        return error("validacion", "Pásame el `tarea_id` de lo no cumplido.")
    decision = (params.get("decision") or "").strip().lower()
    if decision not in _DECISIONES:
        return error("validacion", "decision debe ser aceptar / otro_dia / soltar / posponer.")
    if decision == "posponer":
        decision = "otro_dia"
    # `aplicar_rollover` lleva su propio resultado: ok + flags (no_existe /
    # sin_hueco) que la app y la IA interpretan. NO los convertimos en error
    # HTTP: "no hay hueco" es un resultado honesto válido (200), no un fallo —
    # se preserva el contrato del endpoint /rollover/decidir.
    res = await rollover.aplicar_rollover(db, tarea_id=tarea_id, decision=decision)
    return ok(res)


# ── Registro ──────────────────────────────────────────────────────────────────


def registrar(reg: RegistroComandos) -> None:
    """Registra los comandos del planificador. Lo llama `comandos/__init__.py`."""
    # Set del día
    reg.registrar(Comando(
        "proponer_set_dia", "Materializa el set propuesto del día (determinista).",
        Riesgo.CONSECUENTE, cmd_proponer_set_dia, ("set_diario_items", "tareas")))
    reg.registrar(Comando(
        "ver_set_dia", "Muestra el set del día.",
        Riesgo.SEGURA, cmd_ver_set_dia, ()))
    reg.registrar(Comando(
        "aceptar_set_dia", "Promueve items del set a Tareas del hub.",
        Riesgo.CONSECUENTE, cmd_aceptar_set_dia, ("tareas", "set_diario_items", "arbol_nodos")))
    reg.registrar(Comando(
        "saltar_item_set", "Salta un item del set (no hoy, sin culpa).",
        Riesgo.CONSECUENTE, cmd_saltar_item_set, ("set_diario_items",)))
    # Bloques
    reg.registrar(Comando(
        "agendar_bloque", "Agenda bloques del plan como tareas (ruta canónica de agregar al día).",
        Riesgo.CONSECUENTE, cmd_agendar_bloque, ("tareas", "set_diario_items", "arbol_nodos")))
    reg.registrar(Comando(
        "saltar_bloque", "Salta un bloque del set del plan del día.",
        Riesgo.CONSECUENTE, cmd_saltar_bloque, ("set_diario_items",)))
    reg.registrar(Comando(
        "completar_bloque", "Completa un bloque agendado (cierra tarea y/o nodo).",
        Riesgo.CONSECUENTE, cmd_completar_bloque, ("tareas", "arbol_nodos", "set_diario_items", "proyectos")))
    # Plan / despertar
    reg.registrar(Comando(
        "plan_de_hoy", "Plan del día colocado en ventanas libres (lectura).",
        Riesgo.SEGURA, cmd_plan_de_hoy, ()))
    reg.registrar(Comando(
        "replanificar_dia", "Replanifica el resto del día desde ahora (lectura).",
        Riesgo.SEGURA, cmd_replanificar_dia, ()))
    reg.registrar(Comando(
        "marcar_despertar", "Ancla de despertar de hoy + rundown determinista del día.",
        Riesgo.CONSECUENTE, cmd_marcar_despertar, ("despertar_dia", "set_diario_items")))
    # Rollover
    reg.registrar(Comando(
        "proponer_rollover", "Propuestas de reprogramación de lo no cumplido (lectura).",
        Riesgo.SEGURA, cmd_proponer_rollover, ()))
    reg.registrar(Comando(
        "aplicar_rollover", "Aplica la decisión sobre lo no cumplido (aceptar/otro_dia/soltar).",
        Riesgo.CONSECUENTE, cmd_aplicar_rollover, ("tareas",)))
