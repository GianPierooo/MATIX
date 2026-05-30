"""Router de push / FCM (Push Capa 1).

- `POST /push/registrar-token` — la app guarda su token de FCM (upsert).
- `POST /push/probar` — manda un push de prueba al token dado (o a todos
  los registrados).

Capa 1: el objetivo es que un push de prueba llegue al teléfono. El
scheduler y la migración de los recordatorios reales son capas siguientes.
"""
from __future__ import annotations

import asyncio

from fastapi import APIRouter, Depends, HTTPException, status

from ..db import Postgrest, get_db
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
    """Corre AHORA un tick del scheduler de recordatorios (Push Capa 2), sin
    esperar el minuto. Útil para probar: crea un evento/tarea con
    recordatorio cercano y llama a esto. Devuelve cuántos mandó."""
    from ..matix.recordatorios import revisar_y_enviar

    return await revisar_y_enviar(db)
