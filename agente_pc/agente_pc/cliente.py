"""Cliente WebSocket del agente.

Conexión SALIENTE persistente al cerebro sobre TLS, con reconexión por backoff
exponencial. La PC siempre inicia; nunca abre puertos ni acepta entrantes.

Verificación anti-impostor (decisión de seguridad 6.0a): se exige wss:// (TLS),
el certificado lo valida la cadena de CA del sistema, y el hostname debe
coincidir EXACTAMENTE con host_esperado. Sin pinning (sobrevive a la rotación
normal de certificados del proveedor).
"""
from __future__ import annotations

import asyncio
import json
import random
import ssl
from collections.abc import Callable
from urllib.parse import urlparse

from websockets.asyncio.client import connect
from websockets.exceptions import WebSocketException

from . import auditoria
from .config import ConfigAgente
from .registro import Contexto, Registro

BACKOFF_MIN = 1.0
BACKOFF_MAX = 60.0
PING_INTERVAL = 20.0
PING_TIMEOUT = 20.0
# Un listado de nombres nunca llega a esto; corta payloads anómalos.
MAX_MENSAJE = 256 * 1024  # 256 KiB


class SeguridadConexion(Exception):
    """La URL del cerebro no pasa las verificaciones de seguridad."""


def _contexto_ssl(config: ConfigAgente) -> ssl.SSLContext:
    u = urlparse(config.cerebro_ws_url)
    if u.scheme != "wss":
        raise SeguridadConexion("la URL del cerebro debe ser wss:// (TLS obligatorio)")
    if (u.hostname or "").lower() != config.host_esperado.lower():
        raise SeguridadConexion(
            f"host inesperado: {u.hostname!r} ≠ {config.host_esperado!r}"
        )
    ctx = ssl.create_default_context()
    ctx.check_hostname = True
    ctx.verify_mode = ssl.CERT_REQUIRED
    return ctx


async def _atender(
    msg: dict, registro: Registro, ctx: Contexto, log: Callable[[str], None]
) -> dict:
    rid = msg.get("id")
    nombre = str(msg.get("nombre", ""))
    args = msg.get("args") or {}
    # `confirmado` solo viaja por el canal de ejecución confirmada del cerebro
    # (tras el OK del usuario en la app). Las acciones consecuentes lo exigen.
    confirmado = bool(msg.get("confirmado", False))
    # Logueamos la ruta principal pero NUNCA los args completos: una acción de
    # `crear_apunte` por error podría traer el contenido del archivo, y el
    # audit/transcripción no debe llevar contenido sensible (es la regla 7 de
    # CLAUDE.md). Para el debug, basta el nombre + ruta + confirmado.
    ruta_audit = args.get("ruta") or args.get("origen") or args.get("carpeta") or ""
    log(
        f"acción recibida id={rid} nombre={nombre!r} ruta={ruta_audit!r} "
        f"confirmado={confirmado}"
    )
    resultado = await registro.ejecutar(nombre, args, ctx, confirmado=confirmado)
    estado_str = "ok" if resultado.get("ok") else f"error:{resultado.get('tipo', '?')}"
    log(f"acción resuelta id={rid} resultado={estado_str}")
    auditoria.registrar(
        accion=nombre,
        ruta=str(ruta_audit),
        ok=bool(resultado.get("ok")),
        detalle=str(resultado.get("tipo", "")),
    )
    return {"tipo": "resultado", "id": rid, "resultado": resultado}


async def _sesion(
    config: ConfigAgente,
    registro: Registro,
    ctx: Contexto,
    stop: asyncio.Event,
    log: Callable[[str], None],
) -> None:
    log(f"abriendo WSS hacia {config.cerebro_ws_url}")
    ssl_ctx = _contexto_ssl(config)
    log("TLS preparado; presentando X-Agente-PC-Token y handshake…")
    async with connect(
        config.cerebro_ws_url,
        additional_headers={"X-Agente-PC-Token": config.agente_pc_token},
        ssl=ssl_ctx,
        ping_interval=PING_INTERVAL,
        ping_timeout=PING_TIMEOUT,
        max_size=MAX_MENSAJE,
        open_timeout=20,
    ) as ws:
        log("handshake OK: cerebro aceptó el token (auth confirmada).")
        await ws.send(json.dumps({"tipo": "hola", "agente": "matix-pc"}))
        log("'hola' enviado; esperando acciones del cerebro.")

        # Si llega el kill switch, cierra el socket para cortar el async-for.
        async def _vigilar_stop() -> None:
            await stop.wait()
            log("kill switch: cerrando WS limpio (code=1001).")
            await ws.close(code=1001, reason="apagado")

        tarea_stop = asyncio.create_task(_vigilar_stop())
        try:
            async for crudo in ws:
                try:
                    msg = json.loads(crudo)
                except (ValueError, TypeError):
                    log("mensaje ignorado: JSON inválido.")
                    continue
                if not isinstance(msg, dict):
                    log("mensaje ignorado: payload no es objeto JSON.")
                    continue
                tipo_msg = msg.get("tipo")
                if tipo_msg == "accion":
                    respuesta = await _atender(msg, registro, ctx, log)
                    await ws.send(json.dumps(respuesta))
                    log(f"resultado devuelto al cerebro id={respuesta.get('id')}")
                else:
                    # Otros tipos (ping de control, mensajes del cerebro): los
                    # ignoramos sin ruido, pero un log de debug ayuda a saber
                    # qué llegó si algún día hay tráfico nuevo.
                    log(f"mensaje no-acción ignorado (tipo={tipo_msg!r}).")
                if stop.is_set():
                    break
        finally:
            tarea_stop.cancel()


async def _esperar_o_stop(segundos: float, stop: asyncio.Event) -> None:
    try:
        await asyncio.wait_for(stop.wait(), timeout=segundos)
    except asyncio.TimeoutError:
        pass


async def correr(
    config: ConfigAgente,
    registro: Registro,
    ctx: Contexto,
    stop: asyncio.Event,
    log: Callable[[str], None] = print,
) -> None:
    backoff = BACKOFF_MIN
    while not stop.is_set():
        try:
            await _sesion(config, registro, ctx, stop, log)
            backoff = BACKOFF_MIN  # cierre limpio → resetea el backoff
        except SeguridadConexion as e:
            # Falla de seguridad (no es wss, host equivocado): reintentar a
            # ciegas no ayuda, pero tampoco morimos en silencio.
            log(f"conexión rechazada por seguridad: {e}")
        except (WebSocketException, OSError, asyncio.TimeoutError) as e:
            log(f"conexión caída ({type(e).__name__}); reintento en ~{backoff:.0f}s")
        if stop.is_set():
            break
        espera = min(backoff, BACKOFF_MAX) * (0.8 + 0.4 * random.random())
        await _esperar_o_stop(espera, stop)
        backoff = min(backoff * 2, BACKOFF_MAX)
