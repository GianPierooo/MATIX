"""Monitoreo de costo de API persistido (operación).

El medidor (`uso.py`) cuenta el gasto en MEMORIA y se pierde al reiniciar. Acá
lo PERSISTIMOS por día (el mes = suma de días) tomando snapshots periódicos del
medidor y sumando el delta a la fila del día. Así Matix responde «¿cuánto gasté
hoy / este mes?» y avisa por push al cruzar un umbral configurable (respetando
el silencio). Instrumentación aditiva: no cambia ninguna feature.

La parte PURA (delta entre snapshots, cruce de umbral, total del mes) se testea
sin BD.
"""
from __future__ import annotations

import logging
from datetime import date, datetime, timezone
from typing import Any
from zoneinfo import ZoneInfo

from ..db import Postgrest
from .uso import medidor

logger = logging.getLogger("matix.costos")
LIMA = ZoneInfo("America/Lima")

# Categorías que persistimos del desglose del medidor.
_CATEGORIAS = ("chat", "whisper", "tts", "embedding", "tavily")

# Acumulado del PROCESO ya contabilizado (por categoría), para sumar solo el
# delta entre snapshots. Se reinicia con el proceso (igual que el medidor).
_ultimo_proceso: dict[str, float] = {}


# ════════════════════════════════════════════════════════════════════════════
# LÓGICA PURA (testeable sin BD)
# ════════════════════════════════════════════════════════════════════════════

def delta_proceso(actual: float, ultimo: float) -> float:
    """Cuánto creció el acumulado del proceso desde el último snapshot. Si el
    acumulado bajó (reinicio del medidor), cuenta el actual como nuevo. PURO."""
    if actual < ultimo:
        return max(0.0, actual)
    return actual - ultimo


def cruza_umbral(total: float, umbral: float) -> bool:
    """¿El total cruzó el umbral? (umbral 0 o negativo = sin umbral). PURO."""
    return umbral > 0 and total >= umbral


def total_mes(filas: list[dict[str, Any]]) -> float:
    """Suma el gasto de un conjunto de filas diarias. PURO."""
    return round(sum(float(f.get("gasto_usd") or 0) for f in filas), 6)


def clave_mes(d: date) -> str:
    """'YYYY-MM' del día. PURO."""
    return f"{d.year:04d}-{d.month:02d}"


# ════════════════════════════════════════════════════════════════════════════
# Persistencia + alerta (impuro)
# ════════════════════════════════════════════════════════════════════════════

async def snapshot_y_alertar(db: Postgrest, *, ahora: datetime | None = None) -> dict:
    """Toma un snapshot del medidor, suma el delta al gasto del día y, si cruza
    el umbral diario/mensual, avisa por push (una vez, respetando silencio).
    Best-effort: nunca lanza."""
    ahora = ahora or datetime.now(timezone.utc)
    hoy = ahora.astimezone(LIMA).date()
    snap = medidor.snapshot()
    cats = snap.get("costos") or {}

    # Delta por categoría desde el último snapshot del proceso.
    deltas: dict[str, float] = {}
    total_delta = 0.0
    for c in _CATEGORIAS:
        actual = float(cats.get(c) or 0)
        d = delta_proceso(actual, _ultimo_proceso.get(c, 0.0))
        _ultimo_proceso[c] = actual
        if d > 0:
            deltas[c] = d
            total_delta += d

    if total_delta > 0:
        await _sumar_al_dia(db, hoy, deltas, total_delta)

    try:
        return await _revisar_umbrales(db, hoy)
    except Exception:  # noqa: BLE001
        logger.exception("costos: fallo revisando umbrales")
        return {"alerta": 0, "error": True}


async def _sumar_al_dia(
    db: Postgrest, hoy: date, deltas: dict[str, float], total_delta: float
) -> None:
    filas = await db.list("costos_api", filters={"fecha": hoy.isoformat()}, limit=1)
    actual = filas[0] if filas else None
    base_total = float((actual or {}).get("gasto_usd") or 0)
    base_cats = dict((actual or {}).get("por_categoria") or {})
    for c, d in deltas.items():
        base_cats[c] = round(float(base_cats.get(c) or 0) + d, 6)
    await db.upsert(
        "costos_api",
        {
            "fecha": hoy.isoformat(),
            "gasto_usd": round(base_total + total_delta, 6),
            "por_categoria": base_cats,
            "actualizado_en": datetime.now(timezone.utc).isoformat(),
        },
        on_conflict="fecha",
    )


async def _revisar_umbrales(db: Postgrest, hoy: date) -> dict:
    cfg_filas = await db.list("config_costos", limit=1)
    cfg = cfg_filas[0] if cfg_filas else {}
    if not cfg.get("activo", True):
        return {"alerta": 0, "off": True}

    fila_hoy = await db.list("costos_api", filters={"fecha": hoy.isoformat()}, limit=1)
    gasto_hoy = float((fila_hoy[0] if fila_hoy else {}).get("gasto_usd") or 0)
    desde = hoy.replace(day=1).isoformat()
    filas_mes = await db.list("costos_api", raw_filters={"fecha": f"gte.{desde}"})
    gasto_mes = total_mes(filas_mes)

    avisos: list[str] = []
    payload: dict[str, Any] = {}
    u_dia = float(cfg.get("umbral_diario_usd") or 0)
    u_mes = float(cfg.get("umbral_mensual_usd") or 0)
    mes = clave_mes(hoy)

    if cruza_umbral(gasto_hoy, u_dia) and cfg.get("alerta_diaria_fecha") != hoy.isoformat():
        avisos.append(f"hoy vas en ${gasto_hoy:.2f} (umbral ${u_dia:.2f})")
        payload["alerta_diaria_fecha"] = hoy.isoformat()
    if cruza_umbral(gasto_mes, u_mes) and cfg.get("alerta_mensual_mes") != mes:
        avisos.append(f"este mes vas en ${gasto_mes:.2f} (umbral ${u_mes:.2f})")
        payload["alerta_mensual_mes"] = mes

    if not avisos:
        return {"alerta": 0}

    enviado = await _push_alerta(db, "💸 Gasto de API: " + "; ".join(avisos) + ".")
    if enviado and cfg.get("id"):
        await db.update("config_costos", cfg["id"], payload)
    return {"alerta": 1 if enviado else 0, "avisos": avisos}


async def _push_alerta(db: Postgrest, cuerpo: str) -> bool:
    """Empuja la alerta de costo respetando el silencio (reusa el motor de
    nudges y FCM existentes). Best-effort."""
    from datetime import datetime as _dt

    from . import recordatorios
    from .planificador_diario import LIMA as _LIMA, _push, _tokens

    local = _dt.now(timezone.utc).astimezone(_LIMA)
    ncfgs = await db.list("config_nudges", limit=1)
    if ncfgs and not recordatorios.permitido_ahora(local, ncfgs[0]):
        return False  # en silencio: no molestamos (se reintenta al próximo tick)
    tokens = await _tokens(db)
    if not tokens:
        return False
    try:
        return await _push(db, tokens, titulo="Gasto de API", cuerpo=cuerpo, payload="uso")
    except RuntimeError:
        return False


async def resumen_gasto(db: Postgrest, *, ahora: datetime | None = None) -> dict[str, Any]:
    """Para responder «¿cuánto gasté hoy / este mes?». Lee lo persistido + el
    gasto de la sesión actual (medidor en memoria)."""
    ahora = ahora or datetime.now(timezone.utc)
    hoy = ahora.astimezone(LIMA).date()
    fila_hoy = await db.list("costos_api", filters={"fecha": hoy.isoformat()}, limit=1)
    row = fila_hoy[0] if fila_hoy else {}
    desde = hoy.replace(day=1).isoformat()
    filas_mes = await db.list("costos_api", raw_filters={"fecha": f"gte.{desde}"})
    return {
        "hoy_usd": round(float(row.get("gasto_usd") or 0), 4),
        "mes_usd": round(total_mes(filas_mes), 4),
        "por_categoria_hoy": row.get("por_categoria") or {},
        "sesion_usd": medidor.snapshot().get("costo_usd", 0),
    }
