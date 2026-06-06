"""Canal cerebro ↔ agente local de la PC (Capa 6 · 6.0a).

- WebSocket `/agente/ws`: el agente de la PC abre esta conexión (saliente desde
  la PC) y se autentica con el header `X-Agente-PC-Token`. El cerebro nunca
  inicia hacia la PC. La conexión queda registrada en `canal` para que las
  tools del modelo puedan enrutar acciones.
- GET `/agente/estado`: la app pregunta si la PC está conectada (para el
  indicador "PC: conectada / desconectada"). Protegido con la API key normal.

Seguridad: el token del agente es un secreto DISTINTO de la API key de la app
(`X-Matix-Key`). Se valida ANTES de aceptar el WebSocket; si no coincide (o no
está configurado en el cerebro), se rechaza el handshake.
"""
from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect

from ..agente.canal import canal
from ..config import settings
from ..security import require_api_key

logger = logging.getLogger("matix.agente")

router = APIRouter(prefix="/agente", tags=["agente"])


@router.websocket("/ws")
async def ws_agente(websocket: WebSocket) -> None:
    token = websocket.headers.get("x-agente-pc-token")
    esperado = settings.agente_pc_token
    if not esperado or token != esperado:
        # Rechazo antes de aceptar el handshake (1008 = policy violation).
        await websocket.close(code=1008)
        return

    await websocket.accept()
    await canal.registrar(websocket)
    logger.info("agente PC conectado")
    try:
        while True:
            msg = await websocket.receive_json()
            if isinstance(msg, dict) and msg.get("tipo") == "resultado":
                canal.resolver(msg)
            # Otros tipos (p. ej. "hola") se ignoran; no son instrucciones.
    except WebSocketDisconnect:
        pass
    except Exception:  # noqa: BLE001 — un mensaje malformado no debe tumbar el server
        logger.exception("error en el WebSocket del agente PC")
    finally:
        await canal.desregistrar(websocket)
        logger.info("agente PC desconectado")


@router.get("/estado", dependencies=[Depends(require_api_key)])
async def estado_agente() -> dict:
    """Estado de conexión de la PC (para el indicador de la app)."""
    return {"conectado": canal.conectado}
