"""Router de push / FCM (Push Capa 1).

- `POST /push/registrar-token` — la app guarda su token de FCM (upsert).
- `POST /push/probar` — manda un push de prueba al token dado (o a todos
  los registrados).

Capa 1: el objetivo es que un push de prueba llegue al teléfono. El
scheduler y la migración de los recordatorios reales son capas siguientes.
"""
from __future__ import annotations

import asyncio

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from ..db import Postgrest, get_db
from ..matix import asistencia_eventos, horario, rendicion_cuentas, rollover
from ..matix.push_fcm import TokenInvalido, enviar_push
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
    if accion not in ("hecho", "manana", "mas_tarde"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Acción desconocida: {body.accion!r}",
        )
    tarea = await db.get("tareas", body.tarea_id)
    if tarea is None:
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
    if accion not in ("si_fui", "no_fui", "reprogramar"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Acción desconocida: {body.accion!r}",
        )
    evento = await db.get("eventos", body.evento_id)
    if evento is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No existe ese evento.",
        )
    return await asistencia_eventos.marcar_asistencia(
        db, evento_id=body.evento_id, accion=accion,
        ahora=datetime.now(timezone.utc),
    )
