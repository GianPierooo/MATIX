"""Automatizaciones que el usuario define (proactividad · v1).

El usuario las crea por chat/voz («cada mañana a las 7 recuérdame revisar mis
tareas», «los lunes hazme un resumen de la semana»). El mismo scheduler del
cerebro (el de rituales/recordatorios) las dispara a su hora y empuja por FCM.

Recurrencias simples (v1): `diaria` (a una hora) o `semanal` (un día ISO a una
hora). Dos tipos de acción:

- `recordatorio`: empuja un texto fijo.
- `accion_ia`: corre un prompt por el chat (puede usar tools como buscar_web) y
  empuja el RESULTADO.

Motor de cadencia (sin tabla de dedup): cada automatización guarda su
`proxima_ejecucion` (UTC). El tick dispara las que ya vencieron y AVANZA la
próxima a la siguiente ocurrencia → nunca se dispara dos veces en el mismo
período. Si una quedó muy atrás (servidor caído > VENTANA), se AVANZA sin
disparar: bien dosificadas, nada de spam.

Horas en America/Lima. NUNCA datos personales ni claves en logs.
"""
from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo

from ..db import Postgrest
from .push_fcm import TokenInvalido, enviar_push

logger = logging.getLogger("matix.automatizaciones")

LIMA = ZoneInfo("America/Lima")
# Catch-up: si la automatización venció hace menos de esto, se dispara al volver;
# más vieja = stale (se avanza sin disparar para no soltar un push a destiempo).
VENTANA = timedelta(hours=2)
# Tope del cuerpo de un push (notificación). La acción de IA puede ser larga; la
# recortamos para la notificación sin reventar el payload de FCM.
_MAX_CUERPO_IA = 1500
_MAX_CUERPO_TXT = 500

RECURRENCIAS = ("diaria", "semanal")
TIPOS = ("recordatorio", "accion_ia")


def _parse(dt_str: str | None) -> datetime | None:
    if not dt_str:
        return None
    try:
        d = datetime.fromisoformat(str(dt_str).replace("Z", "+00:00"))
    except ValueError:
        return None
    if d.tzinfo is None:
        d = d.replace(tzinfo=timezone.utc)
    return d.astimezone(timezone.utc)


def _iso_z(d: datetime) -> str:
    return d.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def proxima_ocurrencia(
    recurrencia: str,
    hora: int,
    minuto: int,
    dia_semana: int | None,
    *,
    desde: datetime,
) -> datetime:
    """La PRÓXIMA vez (UTC) que toca, estrictamente DESPUÉS de `desde`.

    - `diaria`: hoy a hora:minuto si aún no pasó, si no mañana.
    - `semanal`: el próximo `dia_semana` (ISO 1=lun..7=dom) a hora:minuto.

    Función PURA (hora de Lima), testeable sin BD.
    """
    local = desde.astimezone(LIMA)
    cand = local.replace(hour=int(hora), minute=int(minuto), second=0, microsecond=0)
    if recurrencia == "semanal" and dia_semana:
        delta_dias = (int(dia_semana) - cand.isoweekday()) % 7
        cand = cand + timedelta(days=delta_dias)
        if cand <= local:
            cand = cand + timedelta(days=7)
    else:  # diaria (o semanal sin día → la tratamos como diaria)
        if cand <= local:
            cand = cand + timedelta(days=1)
    return cand.astimezone(timezone.utc)


def seleccionar_due(
    autos: list[dict],
    ahora: datetime,
    *,
    ventana: timedelta = VENTANA,
) -> tuple[list[dict], list[dict]]:
    """PURO: parte las automatizaciones en (disparar, avanzar_sin_disparar).

    - disparar: activas cuya `proxima_ejecucion` ya venció y hace menos de
      `ventana` (catch-up).
    - avanzar_sin_disparar: activas vencidas hace MÁS de `ventana` (stale, no
      spameamos) o sin `proxima_ejecucion` calculada todavía.
    """
    disparar: list[dict] = []
    avanzar: list[dict] = []
    for a in autos:
        if not a.get("activa"):
            continue
        prox = _parse(a.get("proxima_ejecucion"))
        if prox is None:
            avanzar.append(a)
            continue
        if prox > ahora:
            continue  # aún no toca
        if (ahora - prox) < ventana:
            disparar.append(a)
        else:
            avanzar.append(a)  # stale: solo reprogramar
    return disparar, avanzar


# ── CRUD (lo usan las tools) ─────────────────────────────────────────


async def crear(db: Postgrest, datos: dict[str, Any]) -> dict[str, Any]:
    """Inserta una automatización ya VALIDADA (la tool valida). Calcula la
    primera `proxima_ejecucion` desde ahora."""
    ahora = datetime.now(timezone.utc)
    prox = proxima_ocurrencia(
        datos["recurrencia"],
        datos["hora"],
        datos.get("minuto", 0),
        datos.get("dia_semana"),
        desde=ahora,
    )
    payload = {**datos, "activa": True, "proxima_ejecucion": _iso_z(prox)}
    return await db.insert("automatizaciones", payload)


async def listar(db: Postgrest) -> list[dict]:
    return await db.list("automatizaciones", order="creada_en.asc", limit=100)


async def eliminar(db: Postgrest, automatizacion_id: str) -> bool:
    fila = await db.get("automatizaciones", automatizacion_id)
    if fila is None:
        return False
    await db.delete("automatizaciones", automatizacion_id)
    return True


def describir_horario(a: dict) -> str:
    """Texto legible del horario, p. ej. «cada día a las 07:00» / «cada lunes a
    las 09:30»."""
    hhmm = f"{int(a.get('hora', 0)):02d}:{int(a.get('minuto', 0)):02d}"
    if a.get("recurrencia") == "semanal" and a.get("dia_semana"):
        dias = {1: "lunes", 2: "martes", 3: "miércoles", 4: "jueves",
                5: "viernes", 6: "sábado", 7: "domingo"}
        return f"cada {dias.get(int(a['dia_semana']), 'semana')} a las {hhmm}"
    return f"cada día a las {hhmm}"


# ── Ejecución (el tick del scheduler) ────────────────────────────────


async def _contenido(db: Postgrest, a: dict) -> tuple[str, str]:
    """(título, cuerpo) del push. Para `accion_ia` corre el prompt por el chat
    (import perezoso para evitar ciclo con tools/chat)."""
    desc = (a.get("descripcion") or "").strip()
    if a.get("tipo") == "accion_ia":
        prompt = (a.get("accion") or desc).strip()
        try:
            from . import chat  # perezoso: rompe el ciclo tools→automatizaciones→chat

            res = await chat.conversar(db, historial=[], mensaje=prompt)
            cuerpo = (res.get("respuesta") or "").strip() or "No obtuve resultado."
        except Exception:  # noqa: BLE001
            logger.exception("automatización IA falló al generar")
            cuerpo = "No pude completar tu automatización esta vez. La reintento la próxima."
        titulo = f"🤖 {desc}" if desc else "🤖 Matix"
        return titulo[:80], cuerpo[:_MAX_CUERPO_IA]
    # recordatorio simple
    cuerpo = (a.get("accion") or desc or "Recordatorio").strip()
    return ("⏰ Recordatorio", cuerpo[:_MAX_CUERPO_TXT])


async def revisar_automatizaciones(
    db: Postgrest, *, ahora: datetime | None = None
) -> dict:
    """Un tick: dispara las automatizaciones vencidas (catch-up) y reprograma su
    próxima. Best-effort: nunca lanza."""
    ahora = ahora or datetime.now(timezone.utc)
    autos = await db.list("automatizaciones", limit=200)
    disparar, avanzar = seleccionar_due(autos, ahora)

    # Reprogramar las stale / sin próxima, SIN disparar (no spam a destiempo).
    for a in avanzar:
        nueva = proxima_ocurrencia(
            a.get("recurrencia", "diaria"),
            a.get("hora", 8),
            a.get("minuto", 0),
            a.get("dia_semana"),
            desde=ahora,
        )
        try:
            await db.update("automatizaciones", a["id"], {"proxima_ejecucion": _iso_z(nueva)})
        except Exception:  # noqa: BLE001
            logger.exception("no pude reprogramar automatización stale")

    if not disparar:
        return {"automatizaciones": 0}

    tokens = [t["token"] for t in await db.list("device_tokens", limit=100)]
    if not tokens:
        return {"automatizaciones": 0, "sin_tokens": True}

    enviados = 0
    for a in disparar:
        titulo, cuerpo = await _contenido(db, a)
        algun_ok = False
        for tok in list(tokens):
            try:
                await asyncio.to_thread(
                    enviar_push,
                    tok,
                    titulo=titulo,
                    cuerpo=cuerpo,
                    data={"payload": f"automatizacion:{a['id']}"},
                )
                algun_ok = True
            except TokenInvalido:
                filas = await db.list("device_tokens", filters={"token": tok}, limit=1)
                if filas:
                    await db.delete("device_tokens", filas[0]["id"])
                tokens.remove(tok)
            except RuntimeError as e:
                logger.error("scheduler automatizaciones: FCM no configurado (%s)", e)
                return {"automatizaciones": enviados, "error": "fcm_no_config"}
            except Exception:  # noqa: BLE001
                logger.exception("scheduler automatizaciones: fallo mandando push")

        # Reprogramar la próxima ocurrencia (avanzar = dedup del período).
        nueva = proxima_ocurrencia(
            a.get("recurrencia", "diaria"),
            a.get("hora", 8),
            a.get("minuto", 0),
            a.get("dia_semana"),
            desde=ahora,
        )
        try:
            await db.update("automatizaciones", a["id"], {"proxima_ejecucion": _iso_z(nueva)})
        except Exception:  # noqa: BLE001
            logger.exception("no pude reprogramar automatización tras disparo")
        if algun_ok:
            enviados += 1

    if enviados:
        logger.info("scheduler: %d automatización(es) disparada(s)", enviados)
    return {"automatizaciones": enviados}
