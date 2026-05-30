"""Scheduler de recordatorios por push (Push Capa 2).

Un job que corre cada minuto en el cerebro: mira qué recordatorios de
EVENTOS y TAREAS vencen y manda un push FCM a los tokens registrados, con
título, cuerpo y deep link. Reemplaza a las alarmas locales, que los OEM
(Honor/Huawei) matan en segundo plano.

Diseño:

- Una "ventana" `(ahora - LOOKBACK, ahora + GRACE]` sobre `recordar_en`.
  El GRACE alinea con el borde del minuto; el LOOKBACK hace el catch-up:
  si el cerebro estuvo caído un rato, al volver manda los que vencieron en
  los últimos minutos (sin spamear los muy viejos).
- Dedupe en la tabla `recordatorios_enviados` por
  `(tipo, entidad_id, recordar_en)`: cada momento se manda UNA vez. Si el
  usuario cambia la hora, es otra clave → se vuelve a mandar.
- Tiempos en America/Lima para mostrar; la comparación es absoluta (UTC).

NO hace nudges escalados ni briefing/cierre — eso es Capa 3.
"""
from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from ..db import Postgrest
from .push_fcm import TokenInvalido, enviar_push

logger = logging.getLogger("matix.recordatorios")

LIMA = ZoneInfo("America/Lima")
LOOKBACK = timedelta(minutes=10)
GRACE = timedelta(seconds=90)


@dataclass(frozen=True)
class Recordatorio:
    tipo: str  # 'tarea' | 'evento'
    entidad_id: str
    recordar_en: datetime  # aware (UTC)
    titulo: str
    cuerpo: str
    payload: str  # deep link: 'tarea:<id>' / 'evento:<id>'

    @property
    def clave(self) -> tuple[str, str, int]:
        return (self.tipo, self.entidad_id, int(self.recordar_en.timestamp()))


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
    """ISO en UTC con sufijo Z (sin `+00:00`, que complica el query param)."""
    return d.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _cuerpo_evento(inicia_en: datetime | None, ubicacion: str | None) -> str:
    if ubicacion:
        return ubicacion
    if inicia_en:
        return f"Empieza a las {inicia_en.astimezone(LIMA):%H:%M}."
    return "Tu evento está por empezar."


def seleccionar(
    *,
    tareas: list[dict],
    eventos: list[dict],
    enviados: set[tuple[str, str, int]],
    ahora: datetime,
    lookback: timedelta = LOOKBACK,
    grace: timedelta = GRACE,
) -> list[Recordatorio]:
    """Función PURA: dados los candidatos crudos de la BD, el set de claves
    ya enviadas y `ahora`, devuelve los recordatorios que toca mandar.
    Testeable sin BD ni FCM."""
    inicio = ahora - lookback
    fin = ahora + grace
    out: list[Recordatorio] = []

    for t in tareas:
        r = _parse(t.get("recordar_en"))
        if r is None or not (inicio < r <= fin):
            continue
        rec = Recordatorio(
            tipo="tarea",
            entidad_id=str(t["id"]),
            recordar_en=r,
            titulo=(t.get("titulo") or "Recordatorio").strip(),
            cuerpo="Recordatorio de tu tarea.",
            payload=f"tarea:{t['id']}",
        )
        if rec.clave not in enviados:
            out.append(rec)

    for e in eventos:
        r = _parse(e.get("recordar_en"))
        if r is None or not (inicio < r <= fin):
            continue
        rec = Recordatorio(
            tipo="evento",
            entidad_id=str(e["id"]),
            recordar_en=r,
            titulo=(e.get("titulo") or "Evento").strip(),
            cuerpo=_cuerpo_evento(_parse(e.get("inicia_en")), e.get("ubicacion")),
            payload=f"evento:{e['id']}",
        )
        if rec.clave not in enviados:
            out.append(rec)

    return out


async def revisar_y_enviar(db: Postgrest, *, ahora: datetime | None = None) -> dict:
    """Un tick: busca recordatorios vencidos, manda push y los marca. Best
    effort: nunca lanza (loguea y sigue). Devuelve un resumen."""
    ahora = ahora or datetime.now(timezone.utc)
    desde = _iso_z(ahora - LOOKBACK)

    tareas = await db.list(
        "tareas",
        raw_filters={
            "recordar_en": f"gte.{desde}",
            "completada": "is.false",
            "eliminado_en": "is.null",
        },
        limit=500,
    )
    eventos = await db.list(
        "eventos",
        raw_filters={"recordar_en": f"gte.{desde}", "eliminado_en": "is.null"},
        limit=500,
    )
    enviados_rows = await db.list(
        "recordatorios_enviados",
        raw_filters={"recordar_en": f"gte.{desde}"},
        limit=1000,
    )
    enviados: set[tuple[str, str, int]] = set()
    for row in enviados_rows:
        r = _parse(row.get("recordar_en"))
        if r is not None:
            enviados.add((row["tipo"], str(row["entidad_id"]), int(r.timestamp())))

    pendientes = seleccionar(
        tareas=tareas, eventos=eventos, enviados=enviados, ahora=ahora
    )
    if not pendientes:
        return {"candidatos": len(tareas) + len(eventos), "enviados": 0}

    tokens = [t["token"] for t in await db.list("device_tokens", limit=100)]
    if not tokens:
        # Nada a quién mandar; se reintenta cuando haya tokens (siguen
        # dentro de la ventana).
        return {"candidatos": len(tareas) + len(eventos), "enviados": 0, "sin_tokens": True}

    enviados_ok = 0
    for rec in pendientes:
        algun_ok = False
        for tok in list(tokens):
            try:
                await asyncio.to_thread(
                    enviar_push,
                    tok,
                    titulo=rec.titulo,
                    cuerpo=rec.cuerpo,
                    data={"payload": rec.payload},
                )
                algun_ok = True
            except TokenInvalido:
                filas = await db.list("device_tokens", filters={"token": tok}, limit=1)
                if filas:
                    await db.delete("device_tokens", filas[0]["id"])
                tokens.remove(tok)
            except RuntimeError as e:
                # FCM sin configurar: no tiene sentido seguir este tick.
                logger.error("scheduler: FCM no configurado (%s)", e)
                return {"candidatos": len(pendientes), "enviados": enviados_ok, "error": "fcm_no_config"}
            except Exception:  # noqa: BLE001
                logger.exception("scheduler: fallo mandando push")

        if algun_ok:
            try:
                await db.insert(
                    "recordatorios_enviados",
                    {
                        "tipo": rec.tipo,
                        "entidad_id": rec.entidad_id,
                        "recordar_en": _iso_z(rec.recordar_en),
                    },
                )
                enviados_ok += 1
            except Exception:  # noqa: BLE001
                # Conflicto del unique (carrera): ya estaba marcado.
                logger.debug("recordatorio ya marcado: %s", rec.clave)

    if enviados_ok:
        logger.info("scheduler: %d recordatorio(s) enviado(s) por push", enviados_ok)
    return {"candidatos": len(tareas) + len(eventos), "enviados": enviados_ok}


# ─── Arranque / parada del job (lo llama el lifespan de FastAPI) ──────────
_scheduler = None


def iniciar(db: Postgrest) -> None:
    """Arranca el job cada minuto. Solo si FCM está configurado (si no, no
    tiene sentido y evitamos ruido en los logs / en tests)."""
    global _scheduler
    if _scheduler is not None:
        return
    from ..config import settings

    if not settings.firebase_service_account_json.strip():
        logger.info("scheduler de recordatorios OFF (sin FIREBASE_SERVICE_ACCOUNT_JSON)")
        return

    from apscheduler.schedulers.asyncio import AsyncIOScheduler

    async def _job() -> None:
        try:
            await revisar_y_enviar(db)
        except Exception:  # noqa: BLE001
            logger.exception("scheduler: el tick falló")

    sch = AsyncIOScheduler(timezone=LIMA)
    sch.add_job(
        _job,
        "interval",
        minutes=1,
        # Corre uno apenas arranca (catch-up tras un deploy/reinicio).
        next_run_time=datetime.now(LIMA),
        id="recordatorios",
        max_instances=1,
        coalesce=True,
    )
    sch.start()
    _scheduler = sch
    logger.info("scheduler de recordatorios ON (cada minuto)")


def detener() -> None:
    global _scheduler
    if _scheduler is not None:
        _scheduler.shutdown(wait=False)
        _scheduler = None
