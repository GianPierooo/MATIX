"""Autotest de conexión al cerebro.

Diagnostica de un toque si el agente puede llegar al cerebro y autenticarse:
- lee la config,
- abre la conexión WebSocket TLS (reusa la lógica de `cliente._contexto_ssl`),
- presenta el token en `X-Agente-PC-Token` (mismo handshake que el daemon),
- espera la confirmación del handshake (= el cerebro aceptó; con token malo
  cierra con 1008 ANTES de aceptar),
- imprime un veredicto CLARO y ACCIONABLE,
- cierra LIMPIO. No deja nada corriendo.

Sin reintentos por backoff: el diagnóstico debe ser rápido. Si falla por
"caída pasajera", el daemon normal sí reintentará.
"""
from __future__ import annotations

import asyncio
import socket
import ssl
import sys
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

from websockets.exceptions import (
    ConnectionClosedError,
    InvalidStatus,
    WebSocketException,
)

from .cliente import SeguridadConexion, _contexto_ssl
from .config import ConfigAgente

# Timeout corto del handshake: si tarda más, algo está mal (red caída, host no
# responde, cerebro dormido). El daemon normal tiene 20s; en diagnóstico cortamos
# antes para que el comando no se quede colgado mucho rato.
TIMEOUT_HANDSHAKE = 8.0

def _marcas() -> tuple[str, str]:
    """Marcas de OK/error. Usa Unicode si la consola lo soporta; si no
    (cp1252 en Windows con stdout redirigido), cae a ASCII en vez de
    crashear con UnicodeEncodeError."""
    enc = (getattr(sys.stdout, "encoding", None) or "ascii").lower()
    try:
        "✓✗".encode(enc)
        return "✓", "✗"
    except (LookupError, UnicodeEncodeError):
        return "[OK]", "[X]"


OK, NO = _marcas()


@dataclass(frozen=True)
class Resultado:
    """Resultado estructurado del autotest. PURO (sin red): ideal para tests."""
    ok: bool
    # Código corto para identificar el caso (ok | sin_token | url_no_wss |
    # host_inesperado | dns_no_resuelve | sin_ruta_a_host | conexion_rechazada |
    # tls_invalido | timeout | token_invalido | error_http | allowlist_vacia | ...).
    codigo: str
    titulo: str
    detalle: str = ""
    # Sugerencia accionable (qué hacer ahora). Vacío si todo bien.
    sugerencia: str = ""


def _ok(titulo: str, detalle: str = "") -> Resultado:
    return Resultado(True, "ok", titulo, detalle)


def _err(codigo: str, titulo: str, detalle: str = "", sugerencia: str = "") -> Resultado:
    return Resultado(False, codigo, titulo, detalle, sugerencia)


def diagnosticar_config(config: ConfigAgente) -> Resultado | None:
    """Chequeos PUROS de la config antes de tocar la red. Devuelve un fallo
    accionable (None = config OK, seguir con la red)."""
    if not config.agente_pc_token:
        return _err(
            "sin_token",
            "Falta AGENTE_PC_TOKEN",
            "El agente no tiene el secreto compartido con el cerebro.",
            "Pega en agente_pc/.env el MISMO AGENTE_PC_TOKEN que Railway "
            "(el del cerebro). Sin eso no hay autenticación.",
        )
    if not config.cerebro_ws_url.startswith("wss://"):
        return _err(
            "url_no_wss",
            "La URL del cerebro no es wss://",
            f"CEREBRO_WS_URL={config.cerebro_ws_url!r}",
            "Cámbiala a wss:// (TLS obligatorio) en agente_pc/.env.",
        )
    # Avisos NO bloqueantes (config OK pero algo está flojo): los devolvemos
    # como warning después del veredicto, no aquí.
    return None


def _interpretar_excepcion(exc: BaseException, host: str) -> Resultado:
    """Traduce una excepción de red/WS a un veredicto accionable. PURO."""
    # Token inválido / handshake rechazado por policy: el servidor cierra con
    # 1008 antes de aceptar.
    if isinstance(exc, InvalidStatus):
        try:
            code = exc.response.status_code  # type: ignore[attr-defined]
        except AttributeError:
            code = 0
        if code in (401, 403):
            return _err(
                "token_invalido",
                "Token rechazado por el cerebro",
                f"HTTP {code} en el handshake.",
                "Revisa que AGENTE_PC_TOKEN sea EXACTAMENTE el mismo que en "
                "Railway. Sin espacios, sin saltos de línea.",
            )
        return _err(
            "error_http", f"El cerebro respondió HTTP {code}",
            "El handshake del WebSocket no se completó.",
            "Mira los logs del cerebro (Railway) para entender el rechazo.",
        )
    if isinstance(exc, ConnectionClosedError):
        # Cerrado tras aceptar — caso raro en diagnóstico; suele ser policy.
        # `rcvd.code` es el frame de cierre que mandó el servidor (API nueva de
        # websockets ≥13.1; antes era `exc.code`, ahora deprecado).
        rcvd = getattr(exc, "rcvd", None)
        codigo_cierre = getattr(rcvd, "code", None) if rcvd is not None else None
        if codigo_cierre == 1008:
            return _err(
                "token_invalido",
                "Token rechazado por el cerebro (cerró con 1008)",
                "El servidor aceptó el TCP pero rechazó la auth.",
                "Verifica que AGENTE_PC_TOKEN coincida con el del cerebro.",
            )
        return _err(
            "conexion_cerrada", "El cerebro cerró la conexión",
            str(exc), "Revisa los logs del cerebro y reintenta.",
        )
    if isinstance(exc, ssl.SSLError):
        return _err(
            "tls_invalido", "Falla TLS hacia el cerebro",
            str(exc),
            "Verifica el reloj del sistema y la cadena de CA (¿proxy o "
            "antivirus interceptando TLS?).",
        )
    if isinstance(exc, socket.gaierror):
        return _err(
            "dns_no_resuelve", f"DNS no resolvió {host!r}",
            str(exc),
            "¿Tienes internet? Prueba `ping " + host + "` o revisa tu DNS.",
        )
    if isinstance(exc, asyncio.TimeoutError):
        return _err(
            "timeout", "El handshake con el cerebro venció",
            f"No respondió en {TIMEOUT_HANDSHAKE:.0f}s.",
            "El cerebro puede estar dormido (Railway free tier) o caído. "
            "Reintenta en unos segundos o revisa el estado del servicio.",
        )
    if isinstance(exc, OSError):
        return _err(
            "sin_ruta_a_host", "No alcancé al cerebro",
            f"{type(exc).__name__}: {exc}",
            "Revisa tu red (firewall corporativo, VPN bloqueando 443).",
        )
    if isinstance(exc, WebSocketException):
        return _err(
            "ws_error", "Error de WebSocket en el handshake",
            f"{type(exc).__name__}: {exc}",
            "Revisa la URL y reintenta. Si persiste, mira los logs del cerebro.",
        )
    # Última red de seguridad: nada se traga en silencio.
    return _err(
        "desconocido", "Error inesperado durante el handshake",
        f"{type(exc).__name__}: {exc}",
        "Si el error persiste, copia este mensaje al issue.",
    )


async def _probar_conexion(config: ConfigAgente) -> Resultado:
    """Abre el WS, presenta el token, espera la confirmación del handshake y
    cierra limpio. Si el cerebro rechaza el token, cierra con 1008 ANTES de
    aceptar y `connect()` lanza `InvalidStatus`. Si acepta, ya estás auth."""
    # Import LOCAL para que `agente_pc.autotest` se pueda importar sin red en
    # tests puros (websockets se carga solo al probar la conexión).
    from websockets.asyncio.client import connect

    try:
        ssl_ctx = _contexto_ssl(config)
    except SeguridadConexion as e:
        # Esto cubre "no es wss" y "host inesperado" — la verificación
        # anti-impostor del cliente. Devolvemos accionable.
        return _err(
            "host_inesperado" if "host" in str(e) else "url_no_wss",
            "La URL del cerebro no pasa el control de seguridad",
            str(e),
            f"Revisa CEREBRO_WS_URL y HOST_ESPERADO en agente_pc/.env "
            f"(esperado: {config.host_esperado}).",
        )

    host = config.host_esperado
    try:
        async with asyncio.timeout(TIMEOUT_HANDSHAKE):
            async with connect(
                config.cerebro_ws_url,
                additional_headers={"X-Agente-PC-Token": config.agente_pc_token},
                ssl=ssl_ctx,
                # ping_interval=None: este es un test corto; no queremos pings.
                ping_interval=None,
                open_timeout=TIMEOUT_HANDSHAKE,
                close_timeout=2.0,
            ) as ws:
                # Mismo "hola" que manda el daemon en producción; nos asegura
                # que el canal está realmente abierto bidireccional.
                import json
                await ws.send(json.dumps({"tipo": "hola", "agente": "matix-pc"}))
                # Cierre LIMPIO: 1000 = normal closure.
                await ws.close(code=1000, reason="autotest")
        return _ok(
            f"Conectado a cerebro ({host})",
            "Handshake TLS + token aceptados; canal abierto y cerrado limpio.",
        )
    except BaseException as e:  # noqa: BLE001 — siempre devolvemos veredicto
        return _interpretar_excepcion(e, host)


def _imprimir(res: Resultado, log: Callable[[str], None]) -> None:
    if res.ok:
        log(f"{OK} {res.titulo}")
        if res.detalle:
            log(f"  {res.detalle}")
    else:
        log(f"{NO} {res.titulo}")
        if res.detalle:
            log(f"  detalle: {res.detalle}")
        if res.sugerencia:
            log(f"  qué hacer: {res.sugerencia}")


def _avisos_post(config: ConfigAgente, log: Callable[[str], None]) -> None:
    """Avisos NO bloqueantes tras un veredicto OK (la conexión va; algo del hub
    podría mejorarse)."""
    if not config.allowlist:
        log(
            "  aviso: la allowlist está vacía — el agente no verá ninguna "
            "carpeta hasta que edites AGENTE_PC_ALLOWLIST en agente_pc/.env."
        )


def ejecutar(
    config: ConfigAgente | None = None,
    log: Callable[[str], None] | None = None,
) -> int:
    """Ejecuta el autotest y devuelve el exit code (0 OK, !=0 fallo).

    `config` y `log` son inyectables para tests (sin red).
    """
    log = log or print
    from .config import cargar_config

    config = config or cargar_config()

    # 1) Chequeos puros de config. Si fallan, no tocamos la red.
    falla = diagnosticar_config(config)
    if falla is not None:
        _imprimir(falla, log)
        return 2

    log(f"[autotest] probando conexión a {config.cerebro_ws_url} …")
    resultado = asyncio.run(_probar_conexion(config))
    _imprimir(resultado, log)
    if resultado.ok:
        _avisos_post(config, log)
        return 0
    return 1
