"""Router de push / FCM (Push Capa 1).

- `POST /push/registrar-token` — la app guarda su token de FCM (upsert).
- `POST /push/probar` — manda un push de prueba al token dado (o a todos
  los registrados).
- `POST /push/rendicion-cuentas/accion` — recibe la acción del botón
  (notificación o UI in-app).
- `POST /push/asistencia/accion` — idem para asistencia a eventos.
- `GET  /push/pendientes-confirmacion` — para que la UI in-app muestre las
  tareas/eventos pasados sin confirmar (no dependemos solo de la noti, que en
  MagicOS y similares puede no llegar).
"""
from __future__ import annotations

import asyncio
import logging

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from ..db import Postgrest, get_db
from ..matix import asistencia_eventos, horario, rendicion_cuentas, rollover
from ..matix.push_fcm import TokenInvalido, enviar_push

logger = logging.getLogger("matix.push")
from ..schemas.push import (
    ProbarPushRequest,
    ProbarPushResponse,
    RegistrarTokenRequest,
    RegistrarTokenResponse,
)
from ..security import require_api_key

router = APIRouter(
    prefix="/push",
    tags=["push"],
    dependencies=[Depends(require_api_key)],
)

TABLE = "device_tokens"


@router.post("/registrar-token", response_model=RegistrarTokenResponse)
async def registrar_token(
    body: RegistrarTokenRequest, db: Postgrest = Depends(get_db)
) -> dict:
    token = body.token.strip()
    if not token:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El token está vacío.",
        )
    # Upsert por token (sin on_conflict en el wrapper: chequeamos y
    # actualizamos / insertamos). Re-registrar bumpea actualizado_en.
    existentes = await db.list(TABLE, filters={"token": token}, limit=1)
    if existentes:
        await db.update(
            TABLE, existentes[0]["id"], {"plataforma": body.plataforma}
        )
    else:
        await db.insert(
            TABLE, {"token": token, "plataforma": body.plataforma}
        )
    return {"ok": True}


@router.post("/probar", response_model=ProbarPushResponse)
async def probar(
    body: ProbarPushRequest, db: Postgrest = Depends(get_db)
) -> dict:
    # Tokens destino: el dado, o todos los registrados.
    if body.token and body.token.strip():
        tokens = [body.token.strip()]
    else:
        filas = await db.list(TABLE, limit=100)
        tokens = [f["token"] for f in filas]
    if not tokens:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No hay tokens registrados. Abre la app primero.",
        )

    enviados = 0
    fallidos = 0
    detalle: list[str] = []
    for token in tokens:
        try:
            # firebase_admin es bloqueante → a un thread.
            mid = await asyncio.to_thread(
                enviar_push, token, titulo=body.titulo, cuerpo=body.cuerpo
            )
            enviados += 1
            detalle.append(f"ok:{mid[-12:]}")
        except RuntimeError as e:
            # Config ausente/ inválida: no tiene sentido seguir.
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(e)
            ) from e
        except TokenInvalido:
            # Token muerto: lo borramos para no reintentarlo siempre.
            fallidos += 1
            detalle.append("token_invalido_borrado")
            filas = await db.list(TABLE, filters={"token": token}, limit=1)
            if filas:
                await db.delete(TABLE, filas[0]["id"])
        except Exception as e:  # noqa: BLE001
            fallidos += 1
            detalle.append(f"fail:{type(e).__name__}")

    return {"enviados": enviados, "fallidos": fallidos, "detalle": detalle}


@router.post("/revisar")
async def revisar(db: Postgrest = Depends(get_db)) -> dict:
    """Corre AHORA un tick del scheduler (recordatorios + rituales + rendición
    de cuentas), sin esperar el minuto. Útil para probar: crea un evento/tarea
    con recordatorio cercano (o pon la hora del ritual al minuto actual) y
    llama a esto. Devuelve cuántos mandó."""
    from ..matix.recordatorios import (
        revisar_nudges,
        revisar_rituales,
        revisar_y_enviar,
    )

    recordatorios = await revisar_y_enviar(db)
    rituales = await revisar_rituales(db)
    nudges = await revisar_nudges(db)
    rendicion = await rendicion_cuentas.revisar_rendicion_cuentas(db)
    return {
        "recordatorios": recordatorios,
        "rituales": rituales,
        "nudges": nudges,
        "rendicion_cuentas": rendicion,
    }


# ── Acción del usuario tocando un botón de la notificación ──────────────────


class AccionRendicionCuentas(BaseModel):
    tarea_id: str
    # 'hecho' | 'manana' | 'mas_tarde'
    accion: str


@router.post("/rendicion-cuentas/accion")
async def aplicar_accion(
    body: AccionRendicionCuentas, db: Postgrest = Depends(get_db)
) -> dict:
    """Aplica la acción que el usuario tocó en la notificación de rendición de
    cuentas. Idempotente, robusto al re-touch del mismo botón. El handler de
    background de la app llama aquí — la app no necesita estar abierta.

    Acciones:
    - 'hecho'     → marca la tarea como completada.
    - 'manana'    → reusa `rollover.aplicar_rollover(decision="otro_dia")`.
    - 'mas_tarde' → mueve el `bloque_inicio/bloque_fin` al próximo hueco real
                    de HOY (reusando el cálculo de ventana útil de B). Si ya
                    no hay ventana útil, responde con `tipo=sin_ventana` y la
                    app degrada al "mañana".
    """
    accion = (body.accion or "").strip().lower()
    # Audit explícito para diagnosticar la cadena botón→handler→cerebro: el
    # usuario puede confirmar contra estos logs si su acción llegó. NO loguea
    # contenido sensible (solo el id y la acción).
    logger.info("rc/accion recibida: tarea=%s accion=%s", body.tarea_id, accion)
    if accion not in ("hecho", "manana", "mas_tarde"):
        logger.warning("rc/accion: acción desconocida %r", body.accion)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Acción desconocida: {body.accion!r}",
        )
    tarea = await db.get("tareas", body.tarea_id)
    if tarea is None:
        logger.warning("rc/accion: tarea %s no existe", body.tarea_id)
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No existe esa tarea.",
        )

    ahora = datetime.now(timezone.utc)

    if accion == "hecho":
        await db.update(
            "tareas", body.tarea_id, {"completada": True}
        )
        await rendicion_cuentas.marcar_resuelta(
            db, tarea_id=body.tarea_id, accion=accion, ahora=ahora
        )
        return {"ok": True, "accion": "hecho"}

    if accion == "manana":
        resultado = await rollover.aplicar_rollover(
            db, tarea_id=body.tarea_id, decision="otro_dia", ahora=ahora
        )
        await rendicion_cuentas.marcar_resuelta(
            db, tarea_id=body.tarea_id, accion=accion, ahora=ahora
        )
        return {"ok": True, "accion": "manana", "rollover": resultado}

    # mas_tarde: próximo hueco real de HOY antes del ancla de dormir.
    cfg_h = await horario._config(db)
    local = ahora.astimezone(rendicion_cuentas.LIMA)
    fijos = await horario._compromisos_fijos(
        db, fecha=local.date(), anclas=cfg_h.get("anclas") or []
    )
    dur = int(cfg_h.get("dur_tarea_min", 20))
    ini_min = rendicion_cuentas.proximo_slot_hoy_min(
        fijos,
        ahora_local=local,
        despertar_min=int(cfg_h["hora_despertar"]) * 60,
        dormir_min=int(cfg_h["hora_dormir"]) * 60,
        buffer_min=int(cfg_h["buffer_min"]),
        buffer_pre_sueno_min=int(cfg_h.get("buffer_pre_sueno_min", 0) or 0),
        dur_min=dur,
    )
    if ini_min is None:
        # Ya no hay ventana útil hoy. La app degrada al botón "mañana".
        return {
            "ok": False,
            "tipo": "sin_ventana",
            "mensaje": "Ya no queda ventana útil hoy antes de tu ancla de dormir.",
        }
    # Movemos el bloque a hoy al hueco encontrado (preservando la duración).
    fecha = local.date()
    fin_min = ini_min + dur
    bloque_ini = datetime(
        fecha.year, fecha.month, fecha.day, ini_min // 60, ini_min % 60,
        tzinfo=rendicion_cuentas.LIMA,
    ).astimezone(timezone.utc)
    bloque_fin = datetime(
        fecha.year, fecha.month, fecha.day, fin_min // 60, fin_min % 60,
        tzinfo=rendicion_cuentas.LIMA,
    ).astimezone(timezone.utc)
    await db.update(
        "tareas",
        body.tarea_id,
        {
            "bloque_inicio": bloque_ini.isoformat(),
            "bloque_fin": bloque_fin.isoformat(),
            "vence_en": bloque_fin.isoformat(),
        },
    )
    await rendicion_cuentas.marcar_resuelta(
        db, tarea_id=body.tarea_id, accion=accion, ahora=ahora
    )
    return {
        "ok": True,
        "accion": "mas_tarde",
        "bloque_inicio": bloque_ini.isoformat(),
        "bloque_fin": bloque_fin.isoformat(),
    }


# ── Asistencia a eventos: "¿Fuiste a X?" desde la notificación ──────────────


class AccionAsistencia(BaseModel):
    evento_id: str
    # 'si_fui' | 'no_fui' | 'reprogramar'
    accion: str


@router.post("/asistencia/accion")
async def aplicar_asistencia(
    body: AccionAsistencia, db: Postgrest = Depends(get_db)
) -> dict:
    """Aplica la respuesta de asistencia que el usuario tocó en la notificación.
    Idempotente, con la app cerrada. Marca `eventos.asistencia` y alimenta así el
    motor de evolución (tasas reales).

    - 'si_fui'      → asistencia = 'asistio'.
    - 'no_fui'      → asistencia = 'no_asistio'.
    - 'reprogramar' → 'no_asistio' + intención de reprogramar (el usuario lo
                      reacomoda; no movemos un evento con ubicación a ciegas).
    """
    accion = (body.accion or "").strip().lower()
    logger.info("asistencia/accion recibida: evento=%s accion=%s",
                body.evento_id, accion)
    if accion not in ("si_fui", "no_fui", "reprogramar"):
        logger.warning("asistencia/accion: acción desconocida %r", body.accion)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Acción desconocida: {body.accion!r}",
        )
    evento = await db.get("eventos", body.evento_id)
    if evento is None:
        logger.warning("asistencia/accion: evento %s no existe", body.evento_id)
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No existe ese evento.",
        )
    return await asistencia_eventos.marcar_asistencia(
        db, evento_id=body.evento_id, accion=accion,
        ahora=datetime.now(timezone.utc),
    )


# ── Pendientes de confirmación (in-app: para sobrevivir a MagicOS) ──────────


@router.get("/pendientes-confirmacion")
async def pendientes_confirmacion(db: Postgrest = Depends(get_db)) -> dict:
    """Tareas y eventos PASADOS sin confirmar — los mismos que el tick de
    rendición/asistencia consideraría, pero sin la cadencia de re-alerta.

    Pensado para la UI in-app: como en MagicOS y similares las notificaciones
    pueden no llegar, el seguimiento NO puede vivir solo en la noti. Esta lista
    le permite a la app mostrar "Pendientes de confirmar" en Tu día y el cierre
    del día. Es seguro spammearla (no envía nada, solo lee). Determinista.

    Devuelve:
      `tareas`: tareas no completadas con plazo vencido (mismo set que
        `rollover.tareas_no_cumplidas` — el motor que ya alimentan los pings).
        Devuelve `{id, titulo, vencio_hace_min}`.
      `eventos`: eventos fuera de casa (con ubicación) cuya ocurrencia TERMINÓ
        hoy o ayer y siguen sin `asistencia`. Devuelve `{id, titulo, ubicacion,
        termino_hace_min}`. Solo del día en curso para no saturar; lo viejo se
        olvida (no agobies por algo de hace 3 días).
    """
    from ..matix.asistencia_eventos import LIMA, evento_fuera_de_casa, fin_ocurrencia
    from ..matix.rollover import tareas_no_cumplidas

    ahora = datetime.now(timezone.utc)
    try:
        tareas_raw = await db.list(
            "tareas",
            raw_filters={"eliminado_en": "is.null", "completada": "is.false"},
            limit=500,
        )
    except Exception:  # noqa: BLE001
        tareas_raw = []
    pend_tareas = tareas_no_cumplidas(tareas_raw, ahora)
    tareas_out = []
    for t in pend_tareas:
        plazo = t.get("bloque_fin") or t.get("vence_en") or t.get("bloque_inicio")
        plazo_dt = horario._parse_dt(plazo)
        venc_min = (
            int((ahora - plazo_dt).total_seconds() / 60) if plazo_dt else 0
        )
        tareas_out.append({
            "id": t["id"],
            "titulo": t.get("titulo") or "Tarea",
            "vencio_hace_min": max(0, venc_min),
            "proyecto_id": t.get("proyecto_id"),
        })

    # Eventos: solo los que terminaron hoy o ayer (margen amable para el cierre
    # del día); fuera de casa; sin asistencia confirmada.
    try:
        eventos_raw = await db.list(
            "eventos", raw_filters={"eliminado_en": "is.null"}, limit=500,
        )
    except Exception:  # noqa: BLE001
        eventos_raw = []
    eventos_out: list[dict] = []
    hoy_local = ahora.astimezone(LIMA).date()
    from datetime import timedelta
    for e in eventos_raw:
        if not evento_fuera_de_casa(e) or e.get("todo_el_dia"):
            continue
        if e.get("asistencia"):
            continue
        fin = fin_ocurrencia(e, ahora=ahora)
        if fin is None or fin >= ahora:
            continue
        fin_local_date = fin.astimezone(LIMA).date()
        if fin_local_date < hoy_local - timedelta(days=1):
            continue
        term_min = int((ahora - fin).total_seconds() / 60)
        eventos_out.append({
            "id": str(e["id"]),
            "titulo": e.get("titulo") or "Evento",
            "ubicacion": e.get("ubicacion"),
            "termino_hace_min": max(0, term_min),
        })

    return {
        "tareas": tareas_out,
        "eventos": eventos_out,
        "generado_en": ahora.isoformat(),
    }
