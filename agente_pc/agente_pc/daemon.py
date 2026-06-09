"""Punto de arranque del agente local.

Carga config, aplica las guardas (token presente, no elevado), monta el
registry + contexto de seguridad, y corre el cliente WebSocket hasta el kill
switch (Ctrl+C / SIGTERM).

Filosofía de mensajes: cualquier fallo de arranque debe decir QUÉ está mal Y
QUÉ COMANDO ejecutar para arreglarlo. Sin "access is denied" crípticos, sin
"check your config" vagos. El usuario lee el mensaje, copia el comando, sigue.

También expone el autotest:
    uv run python -m agente_pc --test-connection
"""
from __future__ import annotations

import asyncio
import ctypes
import logging
import os
import signal
import sys
from pathlib import Path

from . import autotest
from .acciones import crear_registro
from .cliente import correr
from .config import RUTA_ENV, ConfigAgente, cargar_config
from .registro import Contexto


def _configurar_logging() -> logging.Logger:
    """Logger `matix.agente` con formato estándar para todo el daemon. UN
    handler — si el módulo se reimporta no se acumulan logs duplicados."""
    log = logging.getLogger("matix.agente")
    log.setLevel(logging.INFO)
    if log.handlers:
        return log
    h = logging.StreamHandler(sys.stderr)
    h.setFormatter(
        logging.Formatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s",
                          datefmt="%H:%M:%S")
    )
    log.addHandler(h)
    return log


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
            "El .venv está ROTO: no encuentro su intérprete de Python. "
            "Regenéralo así (PowerShell o bash):\n"
            "  cd agente_pc\n"
            "  Remove-Item -Recurse -Force .venv   # o `rm -rf .venv` en bash\n"
            "  uv sync"
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
            f"El .venv apunta a un Python que ya no existe ({base}).\n"
            "Probablemente desinstalaste/actualizaste Python. Regenéralo:\n"
            "  cd agente_pc\n"
            "  Remove-Item -Recurse -Force .venv   # o `rm -rf .venv` en bash\n"
            "  uv sync"
        )
    return None


def chequear_env_file() -> str | None:
    """¿Existe `agente_pc/.env`? Si no, mensaje con el `cp` exacto + nota de
    qué rellenar. PURO (solo lee FS)."""
    if RUTA_ENV.exists():
        return None
    raiz = RUTA_ENV.parent.name  # "agente_pc"
    return (
        f"Falta {raiz}/.env (config local del agente, GITIGNORED).\n"
        "Crea uno desde la plantilla y rellena el token:\n"
        f"  cp {raiz}/.env.example {raiz}/.env\n"
        f"Luego edita {raiz}/.env y pon AGENTE_PC_TOKEN igual al de Railway\n"
        "(el que el cerebro usa en la variable AGENTE_PC_TOKEN). Sin eso, el\n"
        "cerebro rechaza la conexión y el agente no arranca."
    )


def diagnosticar_token(config: ConfigAgente) -> str | None:
    """Si el token está mal antes de tocar la red, decirlo con detalle. Detecta:
    - Token vacío (el caso de siempre).
    - Token con espacios al borde (copy-paste pegó un espacio o salto de línea).
    - Token muy corto (típico de placeholder pegado a medias).
    PURO (sin red)."""
    tok = config.agente_pc_token or ""
    if not tok:
        return (
            "Falta AGENTE_PC_TOKEN en agente_pc/.env. Es el MISMO valor que la\n"
            "variable AGENTE_PC_TOKEN del cerebro (en Railway y en\n"
            "cerebro/.env para correr local). Sin este token, el cerebro\n"
            "rechaza la conexión.\n"
            "Si no tienes uno, genera con:\n"
            "  python -c \"import secrets; print(secrets.token_urlsafe(48))\"\n"
            "y pónlo en LOS DOS lados (Railway + agente_pc/.env)."
        )
    if tok != tok.strip():
        return (
            "AGENTE_PC_TOKEN tiene espacios o saltos de línea al borde. Eso\n"
            "te va a dar HTTP 401 en el handshake con el cerebro porque NO\n"
            "coincide byte a byte con el de Railway.\n"
            "Edita agente_pc/.env, deja el token sin comillas y sin espacios\n"
            "antes/después del =. Ejemplo correcto:\n"
            "  AGENTE_PC_TOKEN=abc123...\n"
            "(no `AGENTE_PC_TOKEN= abc123 `)."
        )
    if len(tok) < 24:
        return (
            f"AGENTE_PC_TOKEN parece muy corto ({len(tok)} chars). El cerebro\n"
            "espera el token URLsafe de 48 bytes (~64 chars). ¿Pegaste el\n"
            "placeholder de .env.example en vez del real de Railway?\n"
            "Revisa agente_pc/.env y vuelve a pegar el de Railway entero."
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


async def _run(config: ConfigAgente, log: logging.Logger) -> int:
    stop = asyncio.Event()
    _instalar_senales(stop)
    registro = crear_registro()
    # Fase 6.2: resolvemos la allowlist de apps (verifica que el exe exista y NO
    # esté en la denylist). Cada entrada omitida deja un aviso accionable.
    from . import apps as _apps
    apps_resueltas, avisos_apps = _apps.resolver_apps(config.apps_specs)
    for aviso in avisos_apps:
        log.warning("apps: %s", aviso)
    ctx = Contexto(
        allowlist=config.allowlist,
        max_lectura_bytes=config.agente_pc_max_lectura_kb * 1024,
        apps=apps_resueltas,
    )
    log.info(
        "arranque: %d acciones (%s)",
        len(registro.nombres()), ", ".join(registro.nombres()),
    )
    log.info("arranque: %d carpetas en allowlist", len(config.allowlist))
    for p in config.allowlist:
        log.info("  - permitida: %s", p)
    log.info(
        "arranque: %d apps en allowlist (%s)",
        len(apps_resueltas), ", ".join(sorted(apps_resueltas)) or "ninguna",
    )
    log.info("arranque: conectando a cerebro %s", config.cerebro_ws_url)
    log.info("arranque: host esperado (anti-impostor) %s", config.host_esperado)
    log.info("arranque: corriendo. Ctrl+C para detener (kill switch).")
    # El cliente.correr ya tenía su propio `log` callable — lo enchufamos al
    # logger estructurado para que cada eslabón del WS aparezca con la misma
    # forma que el resto.
    await correr(config, registro, ctx, stop, log=lambda m: log.info("ws: %s", m))
    log.info("detenido.")
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
    log = _configurar_logging()

    # --help SOLO: ningún chequeo lo bloquea, debe poder leerse aunque el
    # entorno esté roto.
    if "--help" in args or "-h" in args:
        print(
            "Uso: python -m agente_pc [--test-connection]\n"
            "\n"
            "  (sin argumentos)    Arranca el daemon y queda corriendo hasta Ctrl+C.\n"
            "  --test-connection   Prueba la conexión al cerebro y sale (diagnóstico).\n"
            "  -h / --help         Muestra esta ayuda.\n"
        )
        return 0

    # 1) .venv: aviso temprano antes de tocar nada. Sin esto, Windows tira
    # "access is denied" críptico cuando el base Python que creó el venv ya no
    # existe. NO es fatal por sí solo — el daemon a veces igual arranca si el
    # venv todavía tiene el python — pero loggeamos.
    aviso_venv = chequear_venv()
    if aviso_venv:
        log.error(".venv: %s", aviso_venv)
        # Si el venv está REALMENTE roto el siguiente paso (cargar config) va
        # a fallar igual: dejamos seguir para que el error real lo confirme.

    # 2) .env: si no existe, no tiene sentido seguir. Mensaje accionable.
    aviso_env = chequear_env_file()
    if aviso_env:
        log.error(".env: %s", aviso_env)
        return 4

    # --test-connection: autotest de extremo a extremo y SALIR. Lo ponemos
    # DESPUÉS del chequeo de .env porque sin .env el autotest no tendría token.
    if "--test-connection" in args:
        return autotest.ejecutar()

    # 3) Carga de config. Si pydantic explota (env malformado, tipos), lo
    # convertimos en mensaje accionable.
    try:
        config = cargar_config()
    except Exception as e:  # noqa: BLE001
        log.error(
            "config: no pude leer agente_pc/.env (%s: %s).\n"
            "Revisa que el formato sea KEY=VALUE por línea, sin comillas "
            "raras. Si dudas, compara con agente_pc/.env.example.",
            type(e).__name__, e,
        )
        return 5

    # 4) Token: mensaje específico por tipo de problema (vacío vs con espacios
    # vs muy corto). El cerebro responde HTTP 401 a token malo; con esto
    # damos la pista ANTES de que la red haga ese viaje.
    aviso_token = diagnosticar_token(config)
    if aviso_token:
        log.error("token: %s", aviso_token)
        return 2

    # 5) Elevación: protección contra correr como admin/root sin saber.
    if _es_elevado() and not config.agente_pc_permitir_elevado:
        log.error(
            "elevación: estás corriendo como administrador/root. El agente "
            "debe correr con permisos MÍNIMOS del usuario.\n"
            "Ciérralo y ábrelo en una sesión normal (sin 'Run as administrator').\n"
            "Override solo a conciencia: pon AGENTE_PC_PERMITIR_ELEVADO=1 en .env."
        )
        return 3

    # 6) Allowlist vacía: NO bloquea (el agente puede arrancar y conectar; el
    # cerebro/usuario pueden ir poblando la allowlist editando .env). Pero
    # avisamos clarito qué pasa.
    if not config.allowlist:
        log.warning(
            "allowlist VACÍA: el agente arrancará pero rechazará TODA acción "
            "que toque archivos hasta que edites AGENTE_PC_ALLOWLIST en "
            "agente_pc/.env (separadas por ';' o saltos de línea)."
        )

    try:
        return asyncio.run(_run(config, log))
    except KeyboardInterrupt:
        log.info("interrumpido por Ctrl+C.")
        return 0
