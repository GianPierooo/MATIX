"""Rollover de tareas no cumplidas + scheduling dinámico (Capa 8).

Cuando una tarea no se hizo a su hora (su bloque) o al cierre del día (su
vencimiento), Matix NO la deja morir callada ni quedarse vencida sin más: busca
el siguiente HUECO libre (hoy, mañana o el próximo día disponible) reusando el
cálculo de ventanas del horario (`horario.ventanas_libres`), y lo PROPONE
tocable (acepto / otro día / lo suelto). Nunca mueve en silencio.

Guardrail honesto contra acumulación: si se arrastran demasiadas cosas, o una
se reprograma una y otra vez, deja de re-agendar a ciegas y lo dice de frente —
esto ya no es de mover de día, toca re-escopar o bajar la carga (se conecta con
la adaptación de ritmo del planificador y el re-scope honesto del motor de
evolución).

La parte PURA (detección, búsqueda de huecos multi-día, umbral de sobrecarga)
está separada y se testea sin BD.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo

from ..db import Postgrest
from . import horario

LIMA = ZoneInfo("America/Lima")

# Umbrales del guardrail anti-acumulación (honesto, sin culpa).
UMBRAL_ARRASTRADAS = 5    # arrastrar tantas cosas ya es "mucho"
UMBRAL_REPETICIONES = 3   # mover lo mismo tantas veces ya es "no es de mover"
HORIZONTE_DIAS = 7        # hasta dónde buscar hueco hacia adelante


# ════════════════════════════════════════════════════════════════════════════
# LÓGICA PURA (testeable sin BD)
# ════════════════════════════════════════════════════════════════════════════

def _parse_dt(valor: Any) -> datetime | None:
    """ISO/UTC tolerante → datetime aware (UTC si no trae tz). PURO."""
    if isinstance(valor, datetime):
        return valor if valor.tzinfo else valor.replace(tzinfo=timezone.utc)
    if not isinstance(valor, str) or not valor:
        return None
    try:
        d = datetime.fromisoformat(valor.replace("Z", "+00:00"))
    except ValueError:
        return None
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)


def plazo_efectivo(tarea: dict[str, Any]) -> datetime | None:
    """El plazo que manda para saber si una tarea 'se pasó de hora': el bloque
    planificado (bloque_fin) si lo tiene, si no su vencimiento (vence_en). PURO."""
    return _parse_dt(tarea.get("bloque_fin")) or _parse_dt(tarea.get("vence_en"))


def tareas_no_cumplidas(
    tareas: list[dict[str, Any]], ahora: datetime
) -> list[dict[str, Any]]:
    """Tareas sin completar (ni en papelera) cuyo plazo efectivo ya pasó respecto
    a `ahora`. Ordenadas por cuán atrás quedaron (lo más viejo primero). PURO."""
    con_plazo: list[tuple[datetime, dict[str, Any]]] = []
    for t in tareas:
        if t.get("completada") or t.get("eliminado_en"):
            continue
        plazo = plazo_efectivo(t)
        if plazo is None or plazo >= ahora:
            continue
        con_plazo.append((plazo, t))
    con_plazo.sort(key=lambda par: par[0])
    return [t for _, t in con_plazo]


def buscar_hueco(
    ventanas_por_dia: list[tuple[int, list[dict[str, int]]]], dur_min: int
) -> dict[str, int] | None:
    """Primer hueco que cabe `dur_min`, en orden de día y de hora. PURO (no muta).
    `ventanas_por_dia`: lista de (offset_dias, [ventanas {ini,fin,dur}]).
    Devuelve {offset, ini, fin} o None si no hay dónde."""
    for offset, ventanas in ventanas_por_dia:
        for v in sorted(ventanas, key=lambda x: x["ini"]):
            if (v["fin"] - v["ini"]) >= dur_min:
                return {"offset": offset, "ini": v["ini"], "fin": v["ini"] + dur_min}
    return None


def colocar_secuencial(
    ventanas_por_dia: list[tuple[int, list[dict[str, int]]]],
    durs: list[int],
    *,
    buffer_min: int = 10,
) -> list[dict[str, int] | None]:
    """Coloca varias duraciones, una tras otra, SIN pisarse: cada colocación
    achica la ventana que usó. Devuelve una lista (mismo largo que `durs`) con
    {offset,ini,fin} o None por cada item. PURO (trabaja sobre copia)."""
    libres = [(off, [dict(v) for v in vs]) for off, vs in ventanas_por_dia]
    out: list[dict[str, int] | None] = []
    for dur in durs:
        elegido: dict[str, int] | None = None
        for off, vs in libres:
            for v in sorted(vs, key=lambda x: x["ini"]):
                if (v["fin"] - v["ini"]) >= dur:
                    ini = v["ini"]
                    v["ini"] = ini + dur + buffer_min
                    elegido = {"offset": off, "ini": ini, "fin": ini + dur}
                    break
            if elegido is not None:
                break
        out.append(elegido)
    return out


def evaluar_sobrecarga(
    arrastradas: list[dict[str, Any]],
    *,
    umbral_cantidad: int = UMBRAL_ARRASTRADAS,
    umbral_repeticiones: int = UMBRAL_REPETICIONES,
) -> dict[str, Any]:
    """¿Se está arrastrando demasiado, o moviendo lo mismo una y otra vez? Lo
    decide HONESTO, sin culpa. PURO. `arrastradas`: dicts con 'titulo' y
    'veces_reprogramada'. Devuelve {sobrecargado, n, peor_titulo, peor_veces,
    mensaje, recomendacion}."""
    n = len(arrastradas)
    peor_titulo: str | None = None
    peor_veces = 0
    for t in arrastradas:
        v = int(t.get("veces_reprogramada") or 0)
        if v > peor_veces:
            peor_veces = v
            peor_titulo = t.get("titulo")

    por_repeticion = peor_veces >= umbral_repeticiones
    por_cantidad = n >= umbral_cantidad

    if por_repeticion:
        mensaje = (
            f"Esto ya lo moviste {peor_veces} veces. No es de cambiarlo de día — "
            "toca achicarlo o soltarlo."
        )
        recomendacion = "reescopar"
    elif por_cantidad:
        mensaje = (
            f"Estás arrastrando {n} cosas. Esto ya no es de mover de día; bajemos "
            "la carga o re-escopemos juntos."
        )
        recomendacion = "bajar_carga"
    else:
        mensaje = None
        recomendacion = None

    return {
        "sobrecargado": por_repeticion or por_cantidad,
        "n": n,
        "peor_titulo": peor_titulo,
        "peor_veces": peor_veces,
        "mensaje": mensaje,
        "recomendacion": recomendacion,
    }


def texto_aviso_rollover(n: int, sobrecarga: dict[str, Any]) -> tuple[str, str]:
    """Título + cuerpo del push DOSIFICADO que nudgea a revisar el rollover. Si
    hay sobrecarga, el push lleva el mensaje honesto (no más 'te lo muevo'). PURO."""
    if sobrecarga.get("sobrecargado") and sobrecarga.get("mensaje"):
        return ("Hablemos de tu carga", sobrecarga["mensaje"])
    if n <= 1:
        return ("Quedó algo sin hacer", "Te propuse cuándo retomarlo. ¿Lo vemos?")
    return (f"Quedaron {n} cosas sin hacer", "Te propuse cuándo retomarlas. ¿Las vemos?")


def cuando_humano(local_ahora: datetime, offset: int, ini_min: int) -> str:
    """Texto corto: 'hoy 15:30' / 'mañana 09:00' / 'el mié 10:00'. PURO."""
    hhmm = horario.min_a_hhmm(ini_min)
    if offset == 0:
        return f"hoy {hhmm}"
    if offset == 1:
        return f"mañana {hhmm}"
    dia = local_ahora + timedelta(days=offset)
    dias_es = ["lun", "mar", "mié", "jue", "vie", "sáb", "dom"]
    return f"el {dias_es[dia.weekday()]} {hhmm}"


# ════════════════════════════════════════════════════════════════════════════
# Orquestación (impura): lee tablas, propone, aplica. Best-effort.
# ════════════════════════════════════════════════════════════════════════════

def _min_a_utc_iso(fecha, minutos: int) -> str:
    """Fecha + minutos (hora Lima) → ISO UTC, para guardar el bloque."""
    m = max(0, min(24 * 60 - 1, int(minutos)))
    dt = datetime(fecha.year, fecha.month, fecha.day, m // 60, m % 60, tzinfo=LIMA)
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


async def _ventanas_proximos_dias(
    db: Postgrest, *, ahora: datetime, max_dias: int
) -> tuple[list[tuple[int, list[dict[str, int]]]], dict[str, Any]]:
    """Construye [(offset, ventanas)] para hoy..hoy+max_dias reusando el horario
    (config + compromisos fijos + ventanas_libres). El día de hoy arranca desde
    la hora actual (no propone en el pasado)."""
    cfg = await horario._config(db)
    despertar = int(cfg["hora_despertar"]) * 60
    dormir = int(cfg["hora_dormir"]) * 60
    buffer_min = int(cfg["buffer_min"])
    anclas = cfg.get("anclas") or []
    local = ahora.astimezone(LIMA)
    out: list[tuple[int, list[dict[str, int]]]] = []
    for off in range(max_dias + 1):
        fecha = (local + timedelta(days=off)).date()
        fijos = await horario._compromisos_fijos(db, fecha=fecha, anclas=anclas)
        desde_min = (local.hour * 60 + local.minute) if off == 0 else None
        ventanas = horario.ventanas_libres(
            fijos, despertar_min=despertar, dormir_min=dormir,
            buffer_min=buffer_min, desde_min=desde_min,
            buffer_pre_sueno_min=int(cfg.get("buffer_pre_sueno_min", 0) or 0),
        )
        out.append((off, ventanas))
    return out, cfg


async def proponer_rollover(
    db: Postgrest,
    *,
    ahora: datetime | None = None,
    hasta_fin_de_hoy: bool = True,
    max_dias: int = HORIZONTE_DIAS,
) -> dict[str, Any]:
    """Detecta lo no cumplido y propone moverlo al siguiente hueco. NO muta nada.
    Devuelve {proposals, sobrecarga}. `hasta_fin_de_hoy=True` (cierre del día)
    cuenta como no cumplido TODO lo que vence hoy; en False solo lo que ya pasó
    su hora. Best-effort."""
    ahora = ahora or datetime.now(timezone.utc)
    local = ahora.astimezone(LIMA)
    limite = ahora
    if hasta_fin_de_hoy:
        fin_hoy = datetime(
            local.year, local.month, local.day, 23, 59, tzinfo=LIMA
        ).astimezone(timezone.utc)
        if fin_hoy > limite:
            limite = fin_hoy

    try:
        tareas = await db.list(
            "tareas",
            raw_filters={"eliminado_en": "is.null", "completada": "is.false"},
            limit=500,
        )
    except Exception:  # noqa: BLE001
        tareas = []
    pendientes = tareas_no_cumplidas(tareas, limite)
    if not pendientes:
        return {"proposals": [], "sobrecarga": evaluar_sobrecarga([])}

    ventanas_dias, cfg = await _ventanas_proximos_dias(
        db, ahora=ahora, max_dias=max_dias
    )
    dur = int(cfg["dur_tarea_min"])
    colocaciones = colocar_secuencial(
        ventanas_dias, [dur] * len(pendientes), buffer_min=int(cfg["buffer_min"])
    )

    proposals: list[dict[str, Any]] = []
    for t, hueco in zip(pendientes, colocaciones):
        propuesta = None
        if hueco is not None:
            fecha_h = (local + timedelta(days=hueco["offset"])).date()
            propuesta = {
                "fecha": fecha_h.isoformat(),
                "inicio": horario.min_a_hhmm(hueco["ini"]),
                "fin": horario.min_a_hhmm(hueco["fin"]),
                "cuando": cuando_humano(local, hueco["offset"], hueco["ini"]),
            }
        plazo = plazo_efectivo(t)
        proposals.append({
            "tarea_id": t["id"],
            "titulo": t.get("titulo") or "Tarea",
            "veces_reprogramada": int(t.get("veces_reprogramada") or 0),
            "vencio_en": plazo.isoformat() if plazo else None,
            "propuesta": propuesta,
        })

    return {"proposals": proposals, "sobrecarga": evaluar_sobrecarga(proposals)}


async def aplicar_rollover(
    db: Postgrest,
    *,
    tarea_id: str,
    decision: str,
    max_dias: int = HORIZONTE_DIAS,
    ahora: datetime | None = None,
) -> dict[str, Any]:
    """Aplica la decisión del usuario sobre una tarea no cumplida:
    - 'aceptar'  → la mueve al siguiente hueco (hoy o adelante).
    - 'otro_dia' → salta el día de hoy y busca el siguiente día disponible.
    - 'soltar'   → a la papelera (recuperable), sin culpa.
    Mueve el BLOQUE (plazo propio), no `vence_en` (la entrega real). Best-effort."""
    ahora = ahora or datetime.now(timezone.utc)

    if decision == "soltar":
        await db.update("tareas", tarea_id, {"eliminado_en": ahora.isoformat()})
        return {"ok": True, "decision": "soltada"}

    tarea = await db.get("tareas", tarea_id)
    if tarea is None:
        return {"ok": False, "no_existe": True}

    ventanas_dias, cfg = await _ventanas_proximos_dias(
        db, ahora=ahora, max_dias=max_dias
    )
    if decision == "otro_dia":
        ventanas_dias = [(off, vs) for off, vs in ventanas_dias if off >= 1]
    dur = int(cfg["dur_tarea_min"])
    hueco = buscar_hueco(ventanas_dias, dur)
    if hueco is None:
        # No re-agendamos a ciegas: lo decimos honestamente.
        return {"ok": False, "sin_hueco": True}

    local = ahora.astimezone(LIMA)
    fecha_h = (local + timedelta(days=hueco["offset"])).date()
    await db.update("tareas", tarea_id, {
        "bloque_inicio": _min_a_utc_iso(fecha_h, hueco["ini"]),
        "bloque_fin": _min_a_utc_iso(fecha_h, hueco["fin"]),
    })
    # El contador alimenta el guardrail; si la migración aún no corrió, no rompe.
    veces = int(tarea.get("veces_reprogramada") or 0) + 1
    try:
        await db.update("tareas", tarea_id, {"veces_reprogramada": veces})
    except Exception:  # noqa: BLE001
        veces = int(tarea.get("veces_reprogramada") or 0)

    return {
        "ok": True,
        "decision": decision,
        "fecha": fecha_h.isoformat(),
        "inicio": horario.min_a_hhmm(hueco["ini"]),
        "cuando": cuando_humano(local, hueco["offset"], hueco["ini"]),
        "veces_reprogramada": veces,
    }
