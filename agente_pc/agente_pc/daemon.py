"""Punto de arranque del agente local.

Carga config, aplica las guardas (token presente, no elevado), monta el
registry + contexto de seguridad, y corre el cliente WebSocket hasta el kill
switch (Ctrl+C / SIGTERM).
"""
from __future__ import annotations

import asyncio
import ctypes
import os
import signal
import sys

from .acciones import crear_registro
from .cliente import correr
from .config import ConfigAgente, cargar_config
from .registro import Contexto


def _es_elevado() -> bool:
    """¿El proceso corre como administrador/root? (best-effort)."""
    try:
        if os.name == "nt":
            return bool(ctypes.windll.shell32.IsUserAnAdmin())  # type: ignore[attr-defined]
        return os.geteuid() == 0  # type: ignore[attr-defined]
    except Exception:
        return False


def _instalar_senales(stop: asyncio.Event) -> None:
    def _parar(*_: object) -> None:
        if not stop.is_set():
            print("\n[agente] kill switch recibido; cerrando…")
            stop.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, _parar)
        except (NotImplementedError, ValueError):
            # Windows no implementa add_signal_handler; SIGINT (Ctrl+C) llega
            # igual por KeyboardInterrupt, capturado en main().
            try:
                signal.signal(sig, _parar)
            except (OSError, ValueError):
                pass


async def _run(config: ConfigAgente) -> int:
    stop = asyncio.Event()
    _instalar_senales(stop)
    registro = crear_registro()
    ctx = Contexto(
        allowlist=config.allowlist,
        max_lectura_bytes=config.agente_pc_max_lectura_kb * 1024,
    )
    print(f"[agente] acciones registradas: {', '.join(registro.nombres())}")
    print(f"[agente] carpetas permitidas: {len(config.allowlist)}")
    print(f"[agente] cerebro: {config.cerebro_ws_url}")
    print("[agente] corriendo. Ctrl+C para detener (kill switch).")
    await correr(config, registro, ctx, stop, log=lambda m: print(f"[agente] {m}"))
    print("[agente] detenido.")
    return 0


def main() -> int:
    config = cargar_config()

    if not config.agente_pc_token:
        print(
            "[agente] ERROR: falta AGENTE_PC_TOKEN en agente_pc/.env "
            "(es el mismo secreto que el cerebro/Railway). No arranco sin él.",
            file=sys.stderr,
        )
        return 2

    if _es_elevado() and not config.agente_pc_permitir_elevado:
        print(
            "[agente] ERROR: estás corriendo como administrador/root. El agente debe "
            "correr con permisos MÍNIMOS del usuario. Ciérralo y ábrelo en una sesión "
            "normal. (Override solo a conciencia: AGENTE_PC_PERMITIR_ELEVADO=1.)",
            file=sys.stderr,
        )
        return 3

    if not config.allowlist:
        print(
            "[agente] aviso: la allowlist está vacía; no veré ninguna carpeta hasta "
            "que edites AGENTE_PC_ALLOWLIST en agente_pc/.env."
        )

    try:
        return asyncio.run(_run(config))
    except KeyboardInterrupt:
        print("\n[agente] interrumpido.")
        return 0
