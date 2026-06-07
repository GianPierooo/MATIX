"""Confirmación de ASISTENCIA a eventos fuera de casa (extensión de la rendición
de cuentas).

Tras un evento FUERA DE CASA (clase, gym, cita — los que tienen `ubicacion`),
Matix pregunta "¿Fuiste a X?" con botones "Sí fui" / "No fui" / "Reprogramar".
La respuesta se guarda en el propio evento (`eventos.asistencia`) y alimenta el
motor de evolución (tasas reales → ajuste del set).

Reusa de raíz, NO duplica:
  - `horario.ocurre_en` / `_parse_dt` para resolver la ocurrencia del día.
  - `permitido_ahora` (silencio nocturno) y los anclas del usuario.
  - `push_fcm.enviar_push` + el canal `matix_recordatorios` ya existentes.
  - El mismo pipeline data→local-notif→botones→handler de la app.

Contenido DETERMINISTA (plantilla, cero LLM). Dedup por `asistencia_preguntada_en`
(no re-preguntar el mismo evento dentro de la ventana). Tono que ACTIVA, nunca
que avergüenza: pregunta directa, de un toque, sin reproches.
"""
from __future__ import annotations

import asyncio
import logging
from datetime import date, datetime, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo

from ..db import Postgrest
from . import horario, recordatorios
from .push_fcm import TokenInvalido, enviar_push

logger = logging.getLogger("matix.asistencia")

LIMA = ZoneInfo("America/Lima")

# Hasta cuántos minutos DESPUÉS de terminar seguimos preguntando (si la app
# estaba cerrada, el tick del minuto lo recoge igual).
VENTANA_POST_MIN = 120
# No re-preguntar el mismo evento dentro de estas horas (dedup; para recurrentes
# permite preguntar de nuevo al día siguiente, ya pasada la ventana).
REPREGUNTAR_HORAS = 6
# Un evento por tick: la asistencia es puntual; si caen dos a la vez, el segundo
# entra al minuto siguiente (sin pisar la notificación del primero).
MAX_POR_TICK = 1


# ════════════════════════════════════════════════════════════════════════════
# PURO (testeable sin BD ni red)
# ════════════════════════════════════════════════════════════════════════════


def evento_fuera_de_casa(evento: dict[str, Any]) -> bool:
    """True si el evento tiene una `ubicacion` → es FUERA DE CASA y merece
    confirmación de asistencia. PURO."""
    return bool((evento.get("ubicacion") or "").strip())


def fin_ocurrencia(evento: dict[str, Any], *, ahora: datetime) -> datetime | None:
    """Fin (UTC, aware) de la ocurrencia del evento relevante a `ahora`. Para
    eventos sueltos: su `termina_en` (o `inicia_en` + 1h). Para recurrentes que
    caen HOY: la hora de fin aplicada a la fecha de hoy. None si no aplica. PURO.
    """
    ini = horario._parse_dt(evento.get("inicia_en"))
    fin = horario._parse_dt(evento.get("termina_en"))
    base = fin if fin is not None else (ini + timedelta(hours=1) if ini else None)
    if base is None:
        return None
    freq = (evento.get("recurrencia_freq") or "").strip()
    if not freq:
        return base
    # Recurrente: solo si ocurre HOY (hora Lima); aplicamos la hora de fin a hoy.
    hoy = ahora.astimezone(LIMA).date()
    if not horario.ocurre_en(evento, hoy):
        return None
    bl = base.astimezone(LIMA)
    fin_hoy = datetime(hoy.year, hoy.month, hoy.day, bl.hour, bl.minute, tzinfo=LIMA)
    return fin_hoy.astimezone(timezone.utc)


def debe_preguntar(
    evento: dict[str, Any],
    *,
    ahora: datetime,
    ventana_min: int = VENTANA_POST_MIN,
    repreguntar_horas: int = REPREGUNTAR_HORAS,
) -> bool:
    """¿Toca preguntar la asistencia de ESTE evento AHORA? PURO.

    Sí cuando: es fuera de casa, no está borrado ni es de todo-el-día, su
    ocurrencia TERMINÓ hace 0..`ventana_min` minutos, y no se preguntó en las
    últimas `repreguntar_horas`. El dedup por `asistencia_preguntada_en` cubre el
    caso recurrente (al día siguiente ya pasó la ventana → se vuelve a preguntar).
    """
    if not evento_fuera_de_casa(evento):
        return False
    if evento.get("eliminado_en") or evento.get("todo_el_dia"):
        return False
    fin = fin_ocurrencia(evento, ahora=ahora)
    if fin is None:
        return False
    minutos = (ahora - fin).total_seconds() / 60
    if not (0 <= minutos <= ventana_min):
        return False
    preg = horario._parse_dt(evento.get("asistencia_preguntada_en"))
    if preg is not None and (ahora - preg) < timedelta(hours=repreguntar_horas):
        return False
    return True


def armar_contenido_asistencia(evento: dict[str, Any]) -> dict[str, Any]:
    """Contenido DETERMINISTA del push de asistencia. Pregunta directa, sin
    reproche. `acciones` en orden visible. PURO."""
    titulo_ev = (evento.get("titulo") or "tu evento").strip()
    if len(titulo_ev) > 40:
        titulo_ev = titulo_ev[:37] + "…"
    return {
        "titulo": f"¿Fuiste a {titulo_ev}?",
        "cuerpo": "Cuéntame para llevar la cuenta real. Un toque y listo.",
        "acciones": ["si_fui", "no_fui", "reprogramar"],
    }


def tasa_asistencia(asistio: int, total: int) -> float | None:
    """Fracción de eventos confirmados a los que el usuario SÍ fue (0..1). None
    si no hay confirmaciones todavía (sin datos no se castiga). PURO."""
    if total <= 0:
        return None
    return asistio / total


def combinar_tasas(cierre: float | None, asistencia: float | None) -> float | None:
    """Combina la tasa de cierre de tareas con la de asistencia para el motor de
    evolución. CONSERVADOR: manda la PEOR señal disponible (nunca infla el set —
    si vienes faltando a eventos o cerrando poco, el día se achica, no crece).
    None si no hay ninguna señal. PURO."""
    vals = [v for v in (cierre, asistencia) if v is not None]
    if not vals:
        return None
    return min(vals)


# ════════════════════════════════════════════════════════════════════════════
# IMPURO (orquesta BD + FCM)
# ════════════════════════════════════════════════════════════════════════════


def _intensidad(cfg_nudges: dict[str, Any] | None) -> str:
    return str((cfg_nudges or {}).get("intensidad") or "intenso")


async def revisar_asistencia(
    db: Postgrest, *, ahora: datetime | None = None
) -> dict[str, Any]:
    """Un tick: detecta eventos fuera de casa recién terminados sin confirmar y
    manda UN push de asistencia con botones. Respeta el silencio nocturno (ni el
    modo máximo dispara fuera de ventana). Best-effort: nunca tumba al scheduler.
    """
    ahora = ahora or datetime.now(timezone.utc)
    local = ahora.astimezone(LIMA)

    cfgs = await db.list("config_nudges", limit=1)
    cfg_nudges = cfgs[0] if cfgs else None
    if cfg_nudges and not recordatorios.permitido_ahora(local, cfg_nudges):
        return {"asistencia": 0, "silencio": True}

    try:
        eventos = await db.list(
            "eventos", raw_filters={"eliminado_en": "is.null"}, limit=500
        )
    except Exception:  # noqa: BLE001
        return {"asistencia": 0, "error": "lectura_eventos"}

    candidatos = [e for e in eventos if debe_preguntar(e, ahora=ahora)]
    if not candidatos:
        return {"asistencia": 0}
    candidatos = candidatos[:MAX_POR_TICK]

    tokens = [t["token"] for t in await db.list("device_tokens", limit=100)]
    if not tokens:
        return {"asistencia": 0, "sin_tokens": True}

    intensidad = _intensidad(cfg_nudges)
    enviados = 0
    for ev in candidatos:
        contenido = armar_contenido_asistencia(ev)
        data = {
            "payload": "asistencia_evento",
            "tipo": "asistencia_evento",
            "evento_id": str(ev["id"]),
            "evento_titulo": (ev.get("titulo") or "tu evento"),
            "acciones": ",".join(contenido["acciones"]),
            "intensidad": intensidad,
            # La asistencia no es "crítico vencido": nunca full-screen sobre lo
            # que estés haciendo. Es una pregunta tranquila tras el evento.
            "critico": "false",
        }
        algun = False
        for tok in list(tokens):
            try:
                await asyncio.to_thread(
                    enviar_push,
                    tok,
                    titulo=contenido["titulo"],
                    cuerpo=contenido["cuerpo"],
                    data=data,
                )
                algun = True
            except TokenInvalido:
                filas = await db.list("device_tokens", filters={"token": tok}, limit=1)
                if filas:
                    await db.delete("device_tokens", filas[0]["id"])
                tokens.remove(tok)
            except RuntimeError as e:
                logger.error("asistencia: FCM no configurado (%s)", e)
                return {"asistencia": 0, "error": "fcm_no_config"}
            except Exception:  # noqa: BLE001
                logger.exception("asistencia: fallo mandando push")
        if algun:
            enviados += 1
            try:
                await db.update(
                    "eventos", ev["id"],
                    {"asistencia_preguntada_en": ahora.isoformat()},
                )
            except Exception:  # noqa: BLE001
                logger.exception("asistencia: no pude marcar preguntada_en")

    return {"asistencia": enviados, "intensidad": intensidad}


async def marcar_asistencia(
    db: Postgrest, *, evento_id: str, accion: str, ahora: datetime | None = None
) -> dict[str, Any]:
    """Aplica la respuesta del usuario a la pregunta de asistencia. Idempotente.

    - 'si_fui'      → asistencia = 'asistio'.
    - 'no_fui'      → asistencia = 'no_asistio'.
    - 'reprogramar' → registra 'no_asistio' y marca que quiere reprogramarlo
                      (el usuario lo reacomoda en el calendario; no auto-movemos
                      un evento con ubicación a ciegas).
    """
    ahora = ahora or datetime.now(timezone.utc)
    mapa = {"si_fui": "asistio", "no_fui": "no_asistio", "reprogramar": "no_asistio"}
    valor = mapa.get(accion)
    if valor is None:
        return {"ok": False, "tipo": "accion_desconocida"}
    campos: dict[str, Any] = {
        "asistencia": valor,
        "asistencia_preguntada_en": ahora.isoformat(),
    }
    await db.update("eventos", evento_id, campos)
    return {"ok": True, "accion": accion, "asistencia": valor,
            "reprogramar": accion == "reprogramar"}


async def tasa_asistencia_reciente(
    db: Postgrest, *, hoy: date, dias: int = 14
) -> float | None:
    """Tasa real de asistencia de los últimos `dias` (eventos confirmados):
    asistió / confirmados. None si no hay datos. Alimenta el motor de evolución.
    """
    desde = (hoy - timedelta(days=dias)).isoformat()
    try:
        eventos = await db.list(
            "eventos",
            raw_filters={
                "eliminado_en": "is.null",
                "asistencia": "not.is.null",
                "asistencia_preguntada_en": f"gte.{desde}",
            },
            limit=500,
        )
    except Exception:  # noqa: BLE001
        return None
    if not eventos:
        return None
    asistio = sum(1 for e in eventos if e.get("asistencia") == "asistio")
    return tasa_asistencia(asistio, len(eventos))
