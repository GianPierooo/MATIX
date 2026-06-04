"""Planificador diario + motor de nudge (perfil profundo · Paso 3).

Lee los árboles (0030) de los proyectos activos y cada día propone un SET chico
y finible de subtareas. El usuario acepta/edita/salta; las aceptadas se
promueven a Tareas del hub. Luego INSISTE sobre el set aceptado-no-cerrado
(exigente pero sano), con anti-fatiga, y cierra el día celebrando + empujando a
dormir a horario.

Reusa el scheduler (recordatorios._job) y FCM (push_fcm.enviar_push).

La parte PURA (selección del set, escalación, anti-fatiga, textos de cierre y
dormir) está separada y se testea sin BD.
"""
from __future__ import annotations

import asyncio
import logging
from datetime import date, datetime, time, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo

from ..db import Postgrest
from . import creacion_proyecto
from .push_fcm import TokenInvalido, enviar_push

logger = logging.getLogger("matix.planificador")

LIMA = ZoneInfo("America/Lima")
VENTANA_DISPARO = timedelta(hours=2)  # catch-up de la propuesta/dormir del día


# ════════════════════════════════════════════════════════════════════════════
# LÓGICA PURA (testeable sin BD)
# ════════════════════════════════════════════════════════════════════════════

def candidatos_proyecto(nodos: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Próximas subtareas DESBLOQUEADAS de un proyecto: la primera hoja FINA
    pendiente de cada fase, en orden (respeta dependencias por orden). Las fases
    GRUESAS (lejanas, sin desglosar) no aportan candidatos — anti-abrumo."""
    hijos: dict[Any, list[dict[str, Any]]] = {}
    for n in nodos:
        hijos.setdefault(n.get("parent_id"), []).append(n)
    for lista in hijos.values():
        lista.sort(key=lambda x: x.get("orden", 0))

    def es_hoja(n: dict) -> bool:
        return not hijos.get(n.get("id"))

    out: list[dict[str, Any]] = []
    for fase in hijos.get(None, []):
        hojas = [h for h in hijos.get(fase.get("id"), []) if es_hoja(h)]
        for h in hojas:
            if h.get("estado") == "hecho":
                continue
            if h.get("granularidad") != "fino":
                continue
            out.append(h)
            break  # solo la PRIMERA pendiente de la fase (desbloqueada)
    return out


def seleccionar_set(
    proyectos: list[dict[str, Any]],
    nodos_por_proyecto: dict[str, list[dict[str, Any]]],
    *,
    tamano: int = 3,
) -> list[dict[str, Any]]:
    """Set del día: ambicioso pero finible. Reparte entre proyectos activos (uno
    de cada uno primero, luego segundos), priorizando por `prioridad`, hasta
    `tamano`. No es «todo lo que existe»."""
    activos = sorted(proyectos, key=lambda p: p.get("prioridad") or 99)
    por_p = {p["id"]: candidatos_proyecto(nodos_por_proyecto.get(p["id"], [])) for p in activos}

    elegidos: list[dict[str, Any]] = []
    ronda = 0
    while len(elegidos) < tamano and any(len(por_p[p["id"]]) > ronda for p in activos):
        for p in activos:
            if len(elegidos) >= tamano:
                break
            cands = por_p[p["id"]]
            if len(cands) > ronda:
                nodo = cands[ronda]
                elegidos.append({
                    "proyecto_id": p["id"],
                    "proyecto": p.get("nombre", ""),
                    "nodo_id": nodo.get("id"),
                    "titulo": nodo.get("titulo", ""),
                    "orden": len(elegidos),
                })
        ronda += 1
    return elegidos


_BASE_INTENSIDAD = {"alta": 45, "media": 90, "baja": 180}  # minutos


def factor_anti_fatiga(racha_sin_progreso: int) -> int:
    """Anti-fatiga: si insisto y NO hay progreso, espacio más ese tipo de nudge
    (sin apagar la insistencia). Multiplicador del intervalo."""
    if racha_sin_progreso <= 1:
        return 1
    if racha_sin_progreso <= 3:
        return 2
    return 4


def intervalo_escalacion(intensidad: str, racha_sin_progreso: int) -> timedelta:
    """Cada cuánto insistir sobre el set, según intensidad y anti-fatiga."""
    base = _BASE_INTENSIDAD.get(intensidad, 45)
    return timedelta(minutes=base * factor_anti_fatiga(racha_sin_progreso))


def tope_escalaciones_dia(intensidad: str) -> int:
    """Tope diario de nudges de escalación (anti-spam), por intensidad."""
    return {"alta": 8, "media": 5, "baja": 3}.get(intensidad, 8)


_ESCALACION = [
    "Te queda {n} del set de hoy. Un empujón y lo cierras. 💪",
    "Vas bien: cierra {n} que falta(n) del set. Tú puedes.",
    "Recta del día: {n} pendiente(s) del set. Dale un ratito.",
    "Cerremos el set de hoy: {n} por terminar. Paso a paso.",
    "Lo mínimo cuenta: avanza 1 del set ({n} pendiente(s)).",
]


def texto_escalacion(pendientes: int, n: int) -> tuple[str, str]:
    """Mensaje firme pero sano (coach, no jefe), rotado por `n`. Apunta a CERRAR
    el set comprometido, incluso lo mínimo."""
    cuerpo = _ESCALACION[n % len(_ESCALACION)].format(n=pendientes)
    return ("Tu set de hoy", cuerpo)


def resumen_cierre(hechos: int, total: int) -> tuple[str, str]:
    """Cierre del día: celebra lo logrado y rueda lo no hecho a mañana SIN
    culpa ni lenguaje de fracaso."""
    if total == 0:
        return ("🌙 Cierre del día", "Hoy no armamos set. Mañana arrancamos fresco. Toca para cerrar el día.")
    if hechos >= total:
        return ("🌙 ¡Set cerrado!", f"Cerraste las {total} de hoy. Bien ahí, en serio. Toca para cerrar el día.")
    pend = total - hechos
    if hechos == 0:
        cuerpo = (f"Hoy no salió el set, y está bien. Lo rodamos a mañana, sin drama. "
                  "Toca para cerrar el día.")
    else:
        cuerpo = (f"Cerraste {hechos} de {total} hoy, eso suma. La(s) {pend} que queda(n) "
                  "la(s) movemos a mañana, sin culpa. Toca para cerrar el día.")
    return ("🌙 Cierre del día", cuerpo)


def texto_dormir() -> tuple[str, str]:
    return ("😴 Hora de ir cerrando", "Vas a dormir antes de las 12, ¿no? Apaga pantallas y descansa; mañana rendimos mejor.")


# ── Skills/hábitos: dosis LIGERA (suave y opcional, nunca insistencia) ────────

_DOSIS_SKILL = [
    "¿Le metes 10 minutos a {n}? Solo si te provoca, sin presión.",
    "Un ratito de {n} hoy suma. Si hoy no, no pasa nada.",
    "¿Te animas a un toque de {n}? Lo justo para disfrutarlo.",
    "Si te queda un hueco, ahí está {n}. Tranqui, es por gusto.",
]


def texto_dosis_skill(nombre: str, n: int) -> tuple[str, str]:
    """Nudge SUAVE y OPCIONAL para una skill/hábito: invita, no exige (un hobby
    fastidiado deja de ser un gusto). Rotado por `n` para no repetir. PURO."""
    cuerpo = _DOSIS_SKILL[n % len(_DOSIS_SKILL)].format(n=nombre)
    return ("Un ratito para ti", cuerpo)


def texto_celebra_skill(nombre: str) -> tuple[str, str]:
    """Celebra una victoria PEQUEÑA de una skill, sin solemnidad. PURO."""
    return ("🎉 Eso suma", f"Le metiste a {nombre} hoy. Pequeño, pero cuenta. Sigue disfrutándolo.")


def elegir_skill_del_dia(
    skills: list[dict[str, Any]], ordinal: int
) -> dict[str, Any] | None:
    """Elige UNA skill del día rotando (round-robin por día) para no nudgear
    siempre la misma. Orden estable por creación/id. PURO."""
    if not skills:
        return None
    orden = sorted(skills, key=lambda p: str(p.get("creado_en") or p.get("id") or ""))
    return orden[ordinal % len(orden)]


# ════════════════════════════════════════════════════════════════════════════
# Helpers de fecha
# ════════════════════════════════════════════════════════════════════════════

def _parse(dt_str: Any) -> datetime | None:
    if isinstance(dt_str, datetime):
        return dt_str if dt_str.tzinfo else dt_str.replace(tzinfo=timezone.utc)
    if not isinstance(dt_str, str) or not dt_str:
        return None
    try:
        d = datetime.fromisoformat(dt_str.replace("Z", "+00:00"))
    except ValueError:
        return None
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)


def _iso_z(d: datetime) -> str:
    return d.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _fin_de_hoy_utc(local: datetime) -> str:
    fin = datetime.combine(local.date(), time(23, 59, 0), tzinfo=LIMA)
    return _iso_z(fin)


# ════════════════════════════════════════════════════════════════════════════
# Construcción / aceptación del set (lo usan las tools y el tick)
# ════════════════════════════════════════════════════════════════════════════

async def construir_set(db: Postgrest, *, ahora: datetime | None = None) -> list[dict[str, Any]]:
    """Construye y PERSISTE el set del día (estado 'propuesto') si aún no
    existe. Rueda lo aceptado-no-hecho de ayer al set de hoy. Devuelve los items
    del día (existentes o recién creados)."""
    ahora = ahora or datetime.now(timezone.utc)
    hoy = ahora.astimezone(LIMA).date()

    existentes = await db.list("set_diario_items", filters={"fecha": hoy.isoformat()}, order="orden.asc")
    if existentes:
        return existentes

    # Rollover: lo aceptado-no-hecho de ayer pasa a hoy (sin culpa).
    ayer = (hoy - timedelta(days=1)).isoformat()
    rollover = await db.list(
        "set_diario_items",
        raw_filters={"fecha": f"eq.{ayer}", "estado": "eq.aceptado"},
    )

    cfg = await _config(db)
    tamano = int(cfg.get("tamano_set", 3))

    items: list[dict[str, Any]] = []
    orden = 0
    for r in rollover:
        items.append(await db.insert("set_diario_items", {
            "fecha": hoy.isoformat(), "proyecto_id": r.get("proyecto_id"),
            "nodo_id": r.get("nodo_id"), "titulo": r.get("titulo"),
            "estado": "aceptado", "tarea_id": r.get("tarea_id"), "orden": orden,
        }))
        if r.get("tarea_id"):  # re-vence la tarea rodada a hoy
            await db.update("tareas", r["tarea_id"], {"vence_en": _fin_de_hoy_utc(ahora.astimezone(LIMA))})
        orden += 1

    faltan = max(0, tamano - len(items))
    if faltan:
        # Solo proyectos de TRABAJO entran al set comprometido: las skills se
        # dosifican aparte (suave y opcional), nunca con la insistencia del set.
        proyectos = creacion_proyecto.solo_proyectos(
            await db.list("proyectos", filters={"estado": "activo"})
        )
        nodos_por_proyecto: dict[str, list[dict]] = {}
        ya_en_set = {r.get("nodo_id") for r in rollover}
        for p in proyectos:
            nodos = await db.list("arbol_nodos", filters={"proyecto_id": p["id"]}, order="orden.asc")
            nodos_por_proyecto[p["id"]] = [n for n in nodos if n["id"] not in ya_en_set]
        nuevos = seleccionar_set(proyectos, nodos_por_proyecto, tamano=faltan)
        for s in nuevos:
            items.append(await db.insert("set_diario_items", {
                "fecha": hoy.isoformat(), "proyecto_id": s["proyecto_id"],
                "nodo_id": s["nodo_id"], "titulo": s["titulo"],
                "estado": "propuesto", "orden": orden,
            }))
            orden += 1
    return items


async def aceptar_items(
    db: Postgrest, *, item_ids: list[str] | None = None, ahora: datetime | None = None
) -> list[dict[str, Any]]:
    """Promueve los items aceptados a Tareas del hub (vencen hoy, fuera del nudge
    genérico para no doble-nudgear), y enlaza tarea_id en el item y en el nodo.
    Sin `item_ids`, acepta todos los 'propuesto' de hoy."""
    ahora = ahora or datetime.now(timezone.utc)
    local = ahora.astimezone(LIMA)
    hoy = local.date().isoformat()
    items = await db.list("set_diario_items", filters={"fecha": hoy})
    objetivo = [
        i for i in items
        if i.get("estado") == "propuesto" and (item_ids is None or i["id"] in item_ids)
    ]
    promovidos: list[dict[str, Any]] = []
    for i in objetivo:
        tarea = await db.insert("tareas", {
            "titulo": i["titulo"],
            "proyecto_id": i.get("proyecto_id"),
            "vence_en": _fin_de_hoy_utc(local),
            "nudges_silenciada": True,  # lo nudgea el motor del SET, no el genérico
        })
        await db.update("set_diario_items", i["id"], {"estado": "aceptado", "tarea_id": tarea["id"]})
        if i.get("nodo_id"):
            await db.update("arbol_nodos", i["nodo_id"], {"tarea_id": tarea["id"], "estado": "en_curso"})
        promovidos.append({**i, "estado": "aceptado", "tarea_id": tarea["id"]})
    return promovidos


async def marcar_item_por_tarea(db: Postgrest, *, tarea_id: str, estado: str) -> int:
    """Sync con el hub: al completar/reabrir la tarea, mueve el item del set."""
    items = await db.list("set_diario_items", filters={"tarea_id": tarea_id})
    nuevo = "hecho" if estado == "hecho" else "aceptado"
    for i in items:
        await db.update("set_diario_items", i["id"], {"estado": nuevo})
    return len(items)


async def _config(db: Postgrest) -> dict[str, Any]:
    filas = await db.list("config_planificacion", limit=1)
    return filas[0] if filas else {}


async def _porque_destacado(db: Postgrest) -> str | None:
    """El porqué/motivación del proyecto activo de mayor prioridad que lo tenga
    (perfil/intake), para tejerlo en el recordatorio de la mañana."""
    try:
        activos = await db.list("proyectos", filters={"estado": "activo"})
    except Exception:  # noqa: BLE001
        return None
    # El porqué de la mañana empuja el TRABAJO, no los hobbies.
    activos = creacion_proyecto.solo_proyectos(activos)
    activos.sort(key=lambda p: p.get("prioridad") or 99)
    for p in activos:
        porque = ((p.get("parametros") or {}).get("porque") or "").strip()
        if porque:
            return porque if porque.endswith((".", "!", "?")) else porque + "."
    return None


# ════════════════════════════════════════════════════════════════════════════
# Ticks del scheduler (best-effort; nunca lanzan)
# ════════════════════════════════════════════════════════════════════════════

async def _tokens(db: Postgrest) -> list[str]:
    return [t["token"] for t in await db.list("device_tokens", limit=100)]


async def _push(db: Postgrest, tokens: list[str], *, titulo: str, cuerpo: str, payload: str) -> bool:
    algun = False
    for tok in list(tokens):
        try:
            await asyncio.to_thread(enviar_push, tok, titulo=titulo, cuerpo=cuerpo, data={"payload": payload})
            algun = True
        except TokenInvalido:
            filas = await db.list("device_tokens", filters={"token": tok}, limit=1)
            if filas:
                await db.delete("device_tokens", filas[0]["id"])
            tokens.remove(tok)
        except RuntimeError:
            raise
        except Exception:  # noqa: BLE001
            logger.exception("planificador: fallo mandando push")
    return algun


async def _ya_enviado(db: Postgrest, tipo: str, fecha: date) -> list[dict]:
    return await db.list(
        "planificacion_enviados",
        filters={"tipo": tipo, "fecha": fecha.isoformat()},
        order="momento.desc",
    )


def _due_hora(local: datetime, hora: int) -> bool:
    prog = local.replace(hour=hora, minute=0, second=0, microsecond=0)
    diff = (local - prog).total_seconds()
    return 0 <= diff < VENTANA_DISPARO.total_seconds()


async def revisar_propuesta(db: Postgrest, *, ahora: datetime | None = None) -> dict:
    """A la hora configurada, arma el set del día y empuja la propuesta (una vez
    por día)."""
    ahora = ahora or datetime.now(timezone.utc)
    cfg = await _config(db)
    if not cfg.get("activo"):
        return {"propuesta": 0, "off": True}
    local = ahora.astimezone(LIMA)
    if not _due_hora(local, int(cfg.get("hora_propuesta", 7))):
        return {"propuesta": 0}
    if await _ya_enviado(db, "propuesta", local.date()):
        return {"propuesta": 0, "ya": True}

    items = await construir_set(db, ahora=ahora)
    pendientes = [i for i in items if i.get("estado") in ("propuesto", "aceptado")]
    if not pendientes:
        return {"propuesta": 0, "sin_items": True}

    tokens = await _tokens(db)
    if not tokens:
        return {"propuesta": 0, "sin_tokens": True}
    cuerpo = f"Tu set de hoy: {len(pendientes)} cosa(s) para mover tus proyectos. Toca para revisarlo y aceptar."
    # Reconecta con el PORQUÉ: si un proyecto activo tiene su motivación en el
    # perfil, la teje en el recordatorio de la mañana (empuja, no castiga).
    porque = await _porque_destacado(db)
    if porque:
        cuerpo = f"Recuerda por qué lo haces: {porque} Tu set de hoy son {len(pendientes)} cosa(s). Toca para verlo."
    try:
        if await _push(db, tokens, titulo="🌅 Tu set de hoy", cuerpo=cuerpo, payload="set_dia"):
            await db.insert("planificacion_enviados", {"tipo": "propuesta", "fecha": local.date().isoformat()})
            return {"propuesta": 1}
    except RuntimeError:
        return {"propuesta": 0, "error": "fcm_no_config"}
    return {"propuesta": 0}


async def revisar_escalacion(db: Postgrest, *, ahora: datetime | None = None) -> dict:
    """Insiste sobre el set ACEPTADO-no-hecho de hoy. Respeta ventanas (config
    de nudges), intensidad, anti-fatiga y un tope diario."""
    ahora = ahora or datetime.now(timezone.utc)
    cfg = await _config(db)
    if not cfg.get("activo"):
        return {"escalacion": 0, "off": True}
    local = ahora.astimezone(LIMA)

    # Reusa las ventanas/silencio del motor de nudges existente.
    from . import recordatorios
    ncfgs = await db.list("config_nudges", limit=1)
    if ncfgs and not recordatorios.permitido_ahora(local, ncfgs[0]):
        return {"escalacion": 0, "fuera_de_ventana": True}

    hoy = local.date().isoformat()
    items = await db.list("set_diario_items", filters={"fecha": hoy})
    aceptados_pend = [i for i in items if i.get("estado") == "aceptado"]
    if not aceptados_pend:
        return {"escalacion": 0, "set_cerrado": True}

    intensidad = cfg.get("intensidad", "alta")
    enviados = await _ya_enviado(db, "escalacion", local.date())
    if len(enviados) >= tope_escalaciones_dia(intensidad):
        return {"escalacion": 0, "tope": True}

    # Anti-fatiga: rachas de escalación SIN que se cerrara nada del set después.
    hechos = [i for i in items if i.get("estado") == "hecho"]
    ult_cierre = max((_parse(i.get("creado_en")) for i in hechos), default=None)
    racha = sum(
        1 for e in enviados
        if ult_cierre is None or (_parse(e.get("momento")) or local) > ult_cierre
    )
    intervalo = intervalo_escalacion(intensidad, racha)
    ultimo = _parse(enviados[0]["momento"]) if enviados else None
    if ultimo is not None and (ahora - ultimo) < intervalo:
        return {"escalacion": 0, "espera": True}

    tokens = await _tokens(db)
    if not tokens:
        return {"escalacion": 0, "sin_tokens": True}
    titulo, cuerpo = texto_escalacion(len(aceptados_pend), len(enviados))
    try:
        if await _push(db, tokens, titulo=titulo, cuerpo=cuerpo, payload="set_dia"):
            await db.insert("planificacion_enviados", {"tipo": "escalacion", "fecha": local.date().isoformat()})
            return {"escalacion": 1, "pendientes": len(aceptados_pend)}
    except RuntimeError:
        return {"escalacion": 0, "error": "fcm_no_config"}
    return {"escalacion": 0}


async def revisar_dormir(db: Postgrest, *, ahora: datetime | None = None) -> dict:
    """Nudge de dormir a horario (meta: antes de las 12), una vez por día."""
    ahora = ahora or datetime.now(timezone.utc)
    cfg = await _config(db)
    if not cfg.get("activo"):
        return {"dormir": 0, "off": True}
    local = ahora.astimezone(LIMA)
    if not _due_hora(local, int(cfg.get("hora_nudge_dormir", 23))):
        return {"dormir": 0}
    if await _ya_enviado(db, "dormir", local.date()):
        return {"dormir": 0, "ya": True}
    tokens = await _tokens(db)
    if not tokens:
        return {"dormir": 0, "sin_tokens": True}
    titulo, cuerpo = texto_dormir()
    try:
        if await _push(db, tokens, titulo=titulo, cuerpo=cuerpo, payload="dormir"):
            await db.insert("planificacion_enviados", {"tipo": "dormir", "fecha": local.date().isoformat()})
            return {"dormir": 1}
    except RuntimeError:
        return {"dormir": 0, "error": "fcm_no_config"}
    return {"dormir": 0}


async def revisar_sugerencia_skill(db: Postgrest, *, ahora: datetime | None = None) -> dict:
    """Dosis LIGERA de skills: a lo más UNA sugerencia suave al día, a su hora,
    dentro de ventana, rotando entre las skills activas. SIN escalación: si el
    usuario no le hace caso, no se insiste (un hobby no se nudgea como una tarea
    comprometida). Respeta el silencio igual que el resto."""
    ahora = ahora or datetime.now(timezone.utc)
    cfg = await _config(db)
    if not cfg.get("activo"):
        return {"sugerencia_skill": 0, "off": True}
    local = ahora.astimezone(LIMA)
    # Solo a su hora (default 18h Lima, ratos libres), con catch-up acotado.
    if not _due_hora(local, int(cfg.get("hora_sugerencia_skill", 18))):
        return {"sugerencia_skill": 0}
    # Respeta silencio/ventana de disponibilidad (reusa el motor de nudges).
    from . import recordatorios
    ncfgs = await db.list("config_nudges", limit=1)
    if ncfgs and not recordatorios.permitido_ahora(local, ncfgs[0]):
        return {"sugerencia_skill": 0, "fuera_de_ventana": True}
    # Una sola al día (anti-spam); nunca se repite ni se escala.
    if await _ya_enviado(db, "sugerencia_skill", local.date()):
        return {"sugerencia_skill": 0, "ya": True}

    skills = creacion_proyecto.solo_skills(
        await db.list("proyectos", filters={"estado": "activo"})
    )
    if not skills:
        return {"sugerencia_skill": 0, "sin_skills": True}
    skill = elegir_skill_del_dia(skills, local.date().toordinal())
    tokens = await _tokens(db)
    if not tokens:
        return {"sugerencia_skill": 0, "sin_tokens": True}
    titulo, cuerpo = texto_dosis_skill(skill["nombre"], local.date().toordinal())
    try:
        if await _push(db, tokens, titulo=titulo, cuerpo=cuerpo, payload=f"proyecto:{skill['id']}"):
            await db.insert(
                "planificacion_enviados",
                {"tipo": "sugerencia_skill", "fecha": local.date().isoformat()},
            )
            return {"sugerencia_skill": 1, "skill": skill["nombre"]}
    except RuntimeError:
        return {"sugerencia_skill": 0, "error": "fcm_no_config"}
    return {"sugerencia_skill": 0}


async def resumen_cierre_db(db: Postgrest, *, ahora: datetime | None = None) -> tuple[int, int]:
    """(hechos, total) del set de hoy, para enriquecer el cierre de las 22h."""
    ahora = ahora or datetime.now(timezone.utc)
    hoy = ahora.astimezone(LIMA).date().isoformat()
    items = await db.list("set_diario_items", filters={"fecha": hoy})
    cuenta = [i for i in items if i.get("estado") in ("aceptado", "hecho")]
    hechos = sum(1 for i in cuenta if i.get("estado") == "hecho")
    return hechos, len(cuenta)
