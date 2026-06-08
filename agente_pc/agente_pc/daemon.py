"""Punto de arranque del agente local.

Carga config, aplica las guardas (token presente, no elevado), monta el
registry + contexto de seguridad, y corre el cliente WebSocket hasta el kill
switch (Ctrl+C / SIGTERM).

También expone el autotest:
    uv run python -m agente_pc --test-connection
"""
from __future__ import annotations

import asyncio
import ctypes
import os
import signal
import sys
from pathlib import Path

from . import autotest
from .acciones import crear_registro
from .cliente import correr
from .config import ConfigAgente, cargar_config
from .registro import Contexto


def chequear_venv() -> str | None:
    """Detecta un `.venv` ROTO antes de fallar críptico (Windows suele tirar
    'access is denied' cuando el `.venv/Scripts/python.exe` apunta a un Python
    que ya no existe — p. ej. tras desinstalar 3.12). Devuelve un mensaje
    accionable o None si está sano. PURO (no muta nada)."""
    raiz = Path(__file__).resolve().parents[1]  # agente_pc/
    venv = raiz / ".venv"
    if not venv.exists():
        # No hay venv todavía: el `uv sync` lo creará. No es un error per se.
        return None
    # Localiza el python del venv (Windows: Scripts/python.exe; POSIX: bin/python).
    candidatos = [
        venv / "Scripts" / "python.exe",
        venv / "bin" / "python",
        venv / "bin" / "python3",
    ]
    py = next((p for p in candidatos if p.exists()), None)
    if py is None:
        return (
            "El .venv está ROTO (no encuentro su intérprete de Python). "
            "Regenéralo: cd agente_pc && rm -rf .venv && uv sync"
        )
    # `pyvenv.cfg` apunta al Python BASE que creó el venv. Si ese base ya no
    # existe (desinstalaste 3.12), invocar al python del venv falla cripticamente.
    cfg = venv / "pyvenv.cfg"
    base: Path | None = None
    if cfg.exists():
        try:
            for linea in cfg.read_text(encoding="utf-8").splitlines():
                if linea.lower().startswith("home"):
                    _, _, valor = linea.partition("=")
                    base = Path(valor.strip())
                    break
        except OSError:
            return None  # no podemos diagnosticar; deja que el daemon siga
    if base is not None and not base.exists():
        return (
            f"El .venv apunta a un Python que ya no existe ({base}). "
            "Regenéralo: cd agente_pc && rm -rf .venv && uv sync"
        )
    return None


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


def main(argv: list[str] | None = None) -> int:
    # Línea a línea aunque la salida esté redirigida (no solo en TTY): así los
    # mensajes de diagnóstico ("conectado al cerebro", errores) aparecen al
    # instante en cualquier terminal o log.
    for flujo in (sys.stdout, sys.stderr):
        try:
            flujo.reconfigure(line_buffering=True)  # type: ignore[union-attr]
        except Exception:  # noqa: BLE001
            pass

    args = argv if argv is not None else sys.argv[1:]

    # Aviso TEMPRANO de .venv roto: vale tanto para el daemon como para el
    # autotest. Sin esto, Windows tira "access is denied" críptico cuando el
    # base Python que creó el venv ya no existe.
    aviso_venv = chequear_venv()
    if aviso_venv:
        print(f"[agente] aviso: {aviso_venv}", file=sys.stderr)

    # --test-connection: autotest de extremo a extremo y SALIR.
    if "--test-connection" in args:
        return autotest.ejecutar()
    if "--help" in args or "-h" in args:
        print(
            "Uso: python -m agente_pc [--test-connection]\n"
            "\n"
            "  (sin argumentos)    Arranca el daemon y queda corriendo hasta Ctrl+C.\n"
            "  --test-connection   Prueba la conexión al cerebro y sale.\n"
        )
        return 0

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
