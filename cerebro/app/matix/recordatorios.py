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
from typing import Any
from zoneinfo import ZoneInfo

from ..db import Postgrest
from .push_fcm import TokenInvalido, enviar_push

logger = logging.getLogger("matix.recordatorios")

LIMA = ZoneInfo("America/Lima")
LOOKBACK = timedelta(minutes=10)
GRACE = timedelta(seconds=90)
# Ventana de catch-up de los rituales diarios: si el cerebro estuvo caído a
# la hora del ritual y vuelve dentro de este rato, igual lo manda (una vez
# por día). Más viejo que esto = se considera stale y no se manda.
VENTANA_RITUAL = timedelta(hours=2)


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


# ─── Rituales: briefing + cierre (diarios) + repaso (semanal) ────────────
def _fecha_dedup(c: dict, local: datetime) -> str:
    """Fecha clave del dedup en `rituales_enviados.fecha`:

    - Rituales DIARIOS (sin `dia_semana`): hoy.
    - Rituales SEMANALES (con `dia_semana`): el LUNES de la semana ISO
      actual, así el ritual no se duplica dentro de la misma semana.
    """
    if c.get("dia_semana"):
        lunes = local.date() - timedelta(days=local.isoweekday() - 1)
        return lunes.isoformat()
    return local.date().isoformat()


def rituales_due(
    configs: list[dict],
    enviados: set[str],
    ahora: datetime,
) -> list[str]:
    """PURO: dados la config de los rituales, cuáles ya se mandaron en su
    período actual (`enviados`, por nombre) y `ahora`, devuelve qué rituales
    toca mandar. Un ritual se manda si está activo, su hora ya pasó y hace
    menos de `VENTANA_RITUAL` (catch-up), y no se mandó aún en su período.

    Un ritual SEMANAL (con `dia_semana`, ISO 1..7) solo se considera el día
    que toca; el resto de días se ignora."""
    local = ahora.astimezone(LIMA)
    out: list[str] = []
    for c in configs:
        if not c.get("activo"):
            continue
        ritual = c.get("ritual")
        if not ritual or ritual in enviados:
            continue
        dia = c.get("dia_semana")
        if dia and local.isoweekday() != int(dia):
            continue
        prog = local.replace(
            hour=int(c["hora"]), minute=int(c["minuto"]), second=0, microsecond=0
        )
        diff = (local - prog).total_seconds()
        if 0 <= diff < VENTANA_RITUAL.total_seconds():
            out.append(ritual)
    return out


async def _contar_hoy(db: Postgrest, ahora: datetime) -> tuple[int, int]:
    """(eventos de hoy, tareas que vencen hoy) en hora de Lima. Best-effort:
    si falla, devuelve (0, 0) y el briefing sale sin números."""
    try:
        hoy = ahora.astimezone(LIMA).date()
        eventos = await db.list(
            "eventos",
            raw_filters={"inicia_en": "not.is.null", "eliminado_en": "is.null"},
            limit=500,
        )
        nev = sum(
            1
            for e in eventos
            if (d := _parse(e.get("inicia_en"))) and d.astimezone(LIMA).date() == hoy
        )
        tareas = await db.list(
            "tareas",
            raw_filters={
                "vence_en": "not.is.null",
                "completada": "is.false",
                "eliminado_en": "is.null",
            },
            limit=500,
        )
        ntar = sum(
            1
            for t in tareas
            if (d := _parse(t.get("vence_en"))) and d.astimezone(LIMA).date() == hoy
        )
        return nev, ntar
    except Exception:  # noqa: BLE001
        logger.exception("briefing: no pude contar lo de hoy")
        return 0, 0


async def _contenido_ritual(
    db: Postgrest, ritual: str, ahora: datetime
) -> tuple[str, str]:
    if ritual == "cierre":
        # Enriquecemos el cierre con el resumen del SET del día (Paso 3):
        # celebra lo hecho y rueda lo pendiente sin culpa. Best-effort.
        try:
            from . import planificador_diario

            hechos, total = await planificador_diario.resumen_cierre_db(db, ahora=ahora)
            if total > 0:
                return planificador_diario.resumen_cierre(hechos, total)
        except Exception:  # noqa: BLE001
            logger.exception("cierre: no pude leer el set del día")
        return (
            "🌙 Cierre del día",
            "¿Qué aprendiste hoy? Anota 3 cosas que sí hiciste y haz tu "
            "descarga mental. Toca para cerrar el día.",
        )
    if ritual == "repaso":
        return (
            "📊 Repaso de la semana",
            "Mira cómo te fue esta semana y planifica la próxima. "
            "Toca para abrir tu repaso con Matix.",
        )
    nev, ntar = await _contar_hoy(db, ahora)
    if nev == 0 and ntar == 0:
        cuerpo = "Día despejado, nada agendado. Toca para ver tu resumen."
    else:
        cuerpo = (
            f"Hoy: {nev} evento(s) y {ntar} tarea(s) que vencen. "
            "Toca para ver tu día."
        )
    return ("🌅 Buenos días", cuerpo)


async def revisar_rituales(db: Postgrest, *, ahora: datetime | None = None) -> dict:
    """Un tick de rituales: si toca el briefing o el cierre (hora de Lima) y
    no se mandó hoy, manda el push. Best-effort."""
    ahora = ahora or datetime.now(timezone.utc)
    local = ahora.astimezone(LIMA)

    configs = await db.list("config_rituales", limit=10)
    if not configs:
        return {"rituales": 0}
    cfg_por_ritual = {c["ritual"]: c for c in configs if c.get("ritual")}

    # Leemos los envíos de la última semana (cubre el dedup diario de hoy y
    # el semanal del lunes de esta semana ISO).
    desde = (local.date() - timedelta(days=8)).isoformat()
    env_rows = await db.list(
        "rituales_enviados", raw_filters={"fecha": f"gte.{desde}"}, limit=50
    )
    # "Enviado en su período actual": para cada ritual, comparamos contra su
    # fecha de dedup (hoy si es diario, lunes de la semana si es semanal).
    enviados = {
        r["ritual"]
        for r in env_rows
        if r["ritual"] in cfg_por_ritual
        and r["fecha"] == _fecha_dedup(cfg_por_ritual[r["ritual"]], local)
    }

    due = rituales_due(configs, enviados, ahora)
    if not due:
        return {"rituales": 0}

    tokens = [t["token"] for t in await db.list("device_tokens", limit=100)]
    if not tokens:
        return {"rituales": 0, "sin_tokens": True}

    enviados_ok = 0
    for ritual in due:
        titulo, cuerpo = await _contenido_ritual(db, ritual, ahora)
        algun_ok = False
        for tok in list(tokens):
            try:
                await asyncio.to_thread(
                    enviar_push,
                    tok,
                    titulo=titulo,
                    cuerpo=cuerpo,
                    data={"payload": ritual},
                )
                algun_ok = True
            except TokenInvalido:
                filas = await db.list("device_tokens", filters={"token": tok}, limit=1)
                if filas:
                    await db.delete("device_tokens", filas[0]["id"])
                tokens.remove(tok)
            except RuntimeError as e:
                logger.error("scheduler rituales: FCM no configurado (%s)", e)
                return {"rituales": enviados_ok, "error": "fcm_no_config"}
            except Exception:  # noqa: BLE001
                logger.exception("scheduler rituales: fallo mandando push")

        if algun_ok:
            try:
                fecha_key = _fecha_dedup(cfg_por_ritual[ritual], local)
                await db.insert(
                    "rituales_enviados", {"ritual": ritual, "fecha": fecha_key}
                )
                enviados_ok += 1
            except Exception:  # noqa: BLE001
                logger.debug("ritual ya marcado en su período: %s", ritual)

        # Al cerrar el día disparamos UNA primera ronda de rendición de cuentas
        # con sus botones de acción, justo cuando el usuario revisa lo del día.
        # Best-effort: si falla, el ritual ya quedó marcado y el tick periódico
        # lo recogerá igual en pasadas siguientes.
        if ritual == "cierre" and algun_ok:
            try:
                from . import rendicion_cuentas

                await rendicion_cuentas.revisar_rendicion_cuentas(db, ahora=ahora)
            except Exception:  # noqa: BLE001
                logger.exception("rendicion_cuentas tras cierre: fallo")

    if enviados_ok:
        logger.info("scheduler: %d ritual(es) enviado(s) por push", enviados_ok)
    return {"rituales": enviados_ok}


# ─── Nudges intensos de tareas (Push Capa 3b) ────────────────────────────
# Textos motivadores, variados, que ACTIVAN (no regañan). Se rotan por un
# contador por tarea para que nunca salga el mismo dos veces seguidas.
_NUDGES_NORMALES = [
    "Un paso pequeño ahora y avanzas. Tú puedes. 💪",
    "Dedícale 10 minutos y mira qué pasa. 🚀",
    "Buen momento para adelantar esto.",
    "Con empezar ya ganaste la mitad. ¡Dale!",
    "Avanza un poco; tu yo de mañana te lo agradece.",
    "Un ratito ahora te quita el peso de después.",
    "Pequeño empujón: esto suma a tu día. ✨",
    "¿Le metes mano? Solo arrancar y fluye.",
    "Hazlo por partes. El primer trozo es el más fácil.",
    "Tienes lo necesario para esto. A por ello.",
]
_NUDGES_URGENTES = [
    "Recta final: un empujón ahora y lo cierras. 🔥",
    "Queda poco tiempo, pero te alcanza. ¡Vamos!",
    "Últimas horas: 15 minutos enfocados marcan la diferencia.",
    "Casi en la meta. Dale el último empujón. 💥",
    "El plazo se acerca; tú puedes cerrarlo ahora.",
    "Momento clave: arranca y no pares hasta terminar.",
    "Sprint final. Concéntrate un rato y listo.",
    "Esto se cierra hoy. Tú mandas. ⏳",
]


def intervalo_nudge(
    restante: timedelta, *, modo_prueba: bool = False
) -> timedelta | None:
    """Curva de intensidad: cada cuánto nudgear según el tiempo que falta
    para el plazo. Más espaciado cuando falta mucho, más seguido al
    acercarse, con un TOPE (nunca cada minuto). `None` = no nudgear.

    En `modo_prueba` la curva se comprime a minutos para verla sin esperar.
    """
    h = restante.total_seconds() / 3600
    if modo_prueba:
        if h < -1:
            return None  # vencida hace rato: paramos
        if h <= 0.25:
            return timedelta(minutes=1)
        if h <= 0.5:
            return timedelta(minutes=2)
        if h <= 1:
            return timedelta(minutes=3)
        return timedelta(minutes=5)
    if h < -24:
        return None  # vencida hace más de un día: dejamos de insistir
    if h <= 3:
        return timedelta(minutes=45)  # últimas 3 h (y vencida hasta -24h)
    if h <= 6:
        return timedelta(minutes=90)
    if h <= 24:
        return timedelta(hours=4)
    if h <= 72:
        return timedelta(hours=12)
    return timedelta(hours=24)  # > 3 días: ~1 por día


def _en_silencio(hora: int, inicio: int, fin: int) -> bool:
    if inicio == fin:
        return False
    if inicio < fin:
        return inicio <= hora < fin
    return hora >= inicio or hora < fin  # cruza medianoche


def permitido_ahora(local: datetime, cfg: dict) -> bool:
    """¿Se puede nudgear AHORA? No durante el silencio, y solo dentro de la
    ventana de disponibilidad del día (hora de Lima). PURO."""
    h = local.hour
    if _en_silencio(
        h, int(cfg.get("silencio_inicio", 22)), int(cfg.get("silencio_fin", 8))
    ):
        return False
    disp = cfg.get("disponibilidad") or {}
    dia = disp.get(str(local.isoweekday())) or {}
    if not dia.get("activo", True):
        return False
    return int(dia.get("inicio", 0)) <= h < int(dia.get("fin", 24))


def texto_nudge(titulo: str, restante: timedelta, n: int) -> tuple[str, str]:
    """Título (= la tarea) + cuerpo motivador, rotado por `n` para variar.
    Usa el pool urgente en las últimas 3 h. PURO."""
    urgente = restante.total_seconds() <= 3 * 3600
    pool = _NUDGES_URGENTES if urgente else _NUDGES_NORMALES
    return (titulo or "Tu tarea", pool[n % len(pool)])


async def revisar_nudges(db: Postgrest, *, ahora: datetime | None = None) -> dict:
    """Un tick de nudges: para cada tarea pendiente con plazo (no silenciada),
    si toca según la curva y estamos en ventana permitida, manda el push."""
    ahora = ahora or datetime.now(timezone.utc)
    cfgs = await db.list("config_nudges", limit=1)
    if not cfgs:
        return {"nudges": 0}
    cfg = cfgs[0]
    if not cfg.get("activo"):
        return {"nudges": 0, "off": True}
    local = ahora.astimezone(LIMA)
    if not permitido_ahora(local, cfg):
        return {"nudges": 0, "fuera_de_ventana": True}
    modo_prueba = bool(cfg.get("modo_prueba"))

    tareas = await db.list(
        "tareas",
        raw_filters={
            "vence_en": "not.is.null",
            "completada": "is.false",
            "eliminado_en": "is.null",
            "nudges_silenciada": "is.false",
        },
        limit=500,
    )
    if not tareas:
        return {"nudges": 0}

    desde = _iso_z(ahora - timedelta(hours=48))
    env = await db.list(
        "nudges_enviados", raw_filters={"momento": f"gte.{desde}"}, limit=2000
    )
    ultimo: dict[str, datetime] = {}
    conteo: dict[str, int] = {}
    for e in env:
        tid = str(e["tarea_id"])
        conteo[tid] = conteo.get(tid, 0) + 1
        d = _parse(e.get("momento"))
        if d and (tid not in ultimo or d > ultimo[tid]):
            ultimo[tid] = d

    tokens = [t["token"] for t in await db.list("device_tokens", limit=100)]
    if not tokens:
        return {"nudges": 0, "sin_tokens": True}

    momento_iso = _iso_z(ahora.replace(second=0, microsecond=0))
    enviados = 0
    for t in tareas:
        tid = str(t["id"])
        vence = _parse(t.get("vence_en"))
        if vence is None:
            continue
        interval = intervalo_nudge(vence - ahora, modo_prueba=modo_prueba)
        if interval is None:
            continue
        last = ultimo.get(tid)
        if last is not None and (ahora - last) < interval:
            continue
        titulo, cuerpo = texto_nudge(
            t.get("titulo") or "Tu tarea", vence - ahora, conteo.get(tid, 0)
        )
        algun_ok = False
        for tok in list(tokens):
            try:
                await asyncio.to_thread(
                    enviar_push,
                    tok,
                    titulo=titulo,
                    cuerpo=cuerpo,
                    data={"payload": f"tarea:{tid}"},
                )
                algun_ok = True
            except TokenInvalido:
                filas = await db.list("device_tokens", filters={"token": tok}, limit=1)
                if filas:
                    await db.delete("device_tokens", filas[0]["id"])
                tokens.remove(tok)
            except RuntimeError as e:
                logger.error("scheduler nudges: FCM no configurado (%s)", e)
                return {"nudges": enviados, "error": "fcm_no_config"}
            except Exception:  # noqa: BLE001
                logger.exception("scheduler nudges: fallo mandando push")
        if algun_ok:
            try:
                await db.insert(
                    "nudges_enviados", {"tarea_id": tid, "momento": momento_iso}
                )
                enviados += 1
            except Exception:  # noqa: BLE001
                logger.debug("nudge ya marcado este minuto: %s", tid)

    if enviados:
        logger.info("scheduler: %d nudge(s) enviado(s) por push", enviados)
    return {"nudges": enviados}


# ─── Arranque / parada del job (lo llama el lifespan de FastAPI) ──────────
_scheduler = None


async def correr_job(nombre: str, coro: Any) -> bool:
    """Corre un job del scheduler AISLADO, con logging estructurado. Un job que
    falla NO muere en silencio ni tumba a los demás: se loguea con contexto
    (nombre del job + tipo de error, SIN datos sensibles) y se devuelve False.
    Devuelve True si terminó bien."""
    try:
        await coro
        return True
    except Exception as e:  # noqa: BLE001
        logger.error(
            "scheduler job=%s FALLÓ: %s", nombre, type(e).__name__, exc_info=True
        )
        return False


async def _avisar_error_critico(db: Postgrest, nombre: str) -> None:
    """Push de error CRÍTICO (un job clave falló), una vez por día y respetando
    el silencio. Best-effort: nunca lanza."""
    try:
        from .planificador_diario import LIMA as _L, _push, _tokens

        local = datetime.now(timezone.utc).astimezone(_L)
        cfgs = await db.list("config_nudges", limit=1)
        if cfgs and not permitido_ahora(local, cfgs[0]):
            return
        hoy = local.date().isoformat()
        tipo = f"error:{nombre}"
        if await db.list(
            "planificacion_enviados", filters={"tipo": tipo, "fecha": hoy}, limit=1
        ):
            return
        tokens = await _tokens(db)
        if not tokens:
            return
        if await _push(
            db,
            tokens,
            titulo="⚠ Matix: fallo de operación",
            cuerpo=f"Falló «{nombre}» en el servidor. Revisa los logs.",
            payload="uso",
        ):
            await db.insert(
                "planificacion_enviados", {"tipo": tipo, "fecha": hoy}
            )
    except Exception:  # noqa: BLE001
        logger.exception("no pude avisar el error crítico de %s", nombre)


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
        # Cada job corre AISLADO: un fallo se loguea con contexto (nombre + tipo
        # de error, sin datos sensibles) y NO tumba a los demás (correr_job).
        from . import (
            automatizaciones,
            backup,
            costos,
            evolucion_proyecto,
            planificador_diario,
            proactividad,
        )

        await correr_job("recordatorios", revisar_y_enviar(db))
        await correr_job("rituales", revisar_rituales(db))
        await correr_job("nudges", revisar_nudges(db))
        # Rendición de cuentas (Push con botones de acción): chequeo periódico
        # cada minuto, con dedup por tarea + tope de niveles + silencio nocturno.
        from . import rendicion_cuentas
        await correr_job(
            "rendicion_cuentas",
            rendicion_cuentas.revisar_rendicion_cuentas(db),
        )
        await correr_job(
            "automatizaciones", automatizaciones.revisar_automatizaciones(db)
        )
        # Planificador diario: propuesta del set, escalación, dormir, skills.
        await correr_job("planificador.propuesta", planificador_diario.revisar_propuesta(db))
        await correr_job("planificador.escalacion", planificador_diario.revisar_escalacion(db))
        await correr_job("planificador.dormir", planificador_diario.revisar_dormir(db))
        await correr_job(
            "planificador.sugerencia_skill",
            planificador_diario.revisar_sugerencia_skill(db),
        )
        # Motor de evolución: check-in, hitos, hitos de %, estancamiento.
        await correr_job("evolucion.checkin", evolucion_proyecto.revisar_checkin(db))
        await correr_job("evolucion.hitos", evolucion_proyecto.revisar_hitos(db))
        await correr_job("evolucion.hitos_pct", evolucion_proyecto.revisar_hitos_pct(db))
        await correr_job("evolucion.estancamiento", evolucion_proyecto.revisar_estancamiento(db))
        # Motor de proactividad (Capa 8): un aviso anticipatorio a la vez, con
        # frenos firmes (tope, silencio, dedup, ritmo).
        await correr_job("proactividad", proactividad.revisar_proactividad(db))
        # Operación: monitoreo de costo (cada minuto) y backup diario (crítico).
        await correr_job("costos.snapshot", costos.snapshot_y_alertar(db))
        ok_backup = await correr_job("backup", backup.revisar_backup(db))
        if not ok_backup:
            await correr_job("backup.aviso", _avisar_error_critico(db, "backup"))

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
