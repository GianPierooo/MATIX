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

from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect, status
from pydantic import BaseModel

from ..agente.canal import canal
from ..config import settings
from ..security import require_api_key

logger = logging.getLogger("matix.agente")

router = APIRouter(prefix="/agente", tags=["agente"])

# Acciones CONSECUENTES que la app puede ejecutar TRAS la confirmación del
# usuario (el gate del sheet). Whitelist explícita: nada fuera de aquí se
# ejecuta por este canal. La lectura va por las tools del chat, no por aquí.
_ACCIONES_CONFIRMABLES = frozenset(
    {
        # 6.1 — organización de archivos
        "mover_archivo", "renombrar_archivo", "crear_carpeta", "organizar_aplicar",
        # 6.2 — cerrar apps y tareas tipadas (el agente revalida la denylist).
        # abrir_app / abrir_carpeta / crear_documento_word / reproducir_spotify
        # son SEGURAS (reversibles): van directas por el canal, sin este gate.
        "cerrar_app", "ejecutar_tarea",
        # 6.3 — control de pantalla: SOLO la acción irreversible YA confirmada
        # por el usuario en el gate. Los primitivos del bucle (capturar/accion/
        # iniciar/terminar) NO son confirmables por aquí: solo los conduce el
        # cerebro dentro de pc_controlar_pantalla.
        "pantalla_accion_confirmada",
    }
)


class EjecutarAccionBody(BaseModel):
    accion: str
    args: dict = {}


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


@router.post("/ejecutar", dependencies=[Depends(require_api_key)])
async def ejecutar_accion(body: EjecutarAccionBody) -> dict:
    """Ejecuta una acción CONSECUENTE tras la confirmación del usuario en la app.

    El modelo NUNCA llega aquí: sus tools consecuentes solo PROPONEN. Esta ruta
    la llama la app después de que el usuario toca «confirmar» en el sheet. Pone
    `confirmado=true` al cruzar el canal; el agente revalida todas las rutas en
    su borde antes de tocar nada. Si la PC no está conectada, responde limpio.
    """
    if body.accion not in _ACCIONES_CONFIRMABLES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Esa acción no se puede ejecutar por este canal.",
        )
    resultado = await canal.enviar_accion(body.accion, body.args or {}, confirmado=True)
    return {"resultado": resultado}
