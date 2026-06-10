"""Autotest de conexión: lógica PURA (sin red) + el diagnóstico del .venv.

La parte de red (`_probar_conexion`) no se cubre aquí — depende del cerebro
real; eso se valida corriendo `python -m agente_pc --test-connection` en el
host. Sí se cubre el clasificador de errores (`_interpretar_excepcion`) con
excepciones inyectadas.
"""
from __future__ import annotations

import asyncio
import socket
import ssl
from pathlib import Path

from agente_pc import autotest, daemon
from agente_pc.config import ConfigAgente


def _config(**overrides) -> ConfigAgente:
    base = {
        "agente_pc_token": "tok",
        "cerebro_ws_url": "wss://matix-production.up.railway.app/api/v1/agente/ws",
        "host_esperado": "matix-production.up.railway.app",
        "agente_pc_allowlist": str(Path.home()),
    }
    base.update(overrides)
    return ConfigAgente(**base)


# ── diagnosticar_config (puro) ──────────────────────────────────────────────


def test_diagnosticar_config_ok_no_devuelve_nada():
    assert autotest.diagnosticar_config(_config()) is None


def test_sin_token_es_accionable():
    r = autotest.diagnosticar_config(_config(agente_pc_token=""))
    assert r is not None and not r.ok
    assert r.codigo == "sin_token"
    assert "AGENTE_PC_TOKEN" in r.sugerencia


def test_url_no_wss_es_accionable():
    r = autotest.diagnosticar_config(
        _config(cerebro_ws_url="ws://matix-production.up.railway.app/api/v1/agente/ws"),
    )
    assert r is not None and r.codigo == "url_no_wss"
    assert "wss" in r.sugerencia.lower()


# ── _interpretar_excepcion (puro): cada excepción → consejo claro ───────────


def test_dns_no_resuelve():
    r = autotest._interpretar_excepcion(socket.gaierror("nombre no resuelve"), "host")
    assert r.codigo == "dns_no_resuelve"
    assert "DNS" in r.titulo or "host" in r.detalle


def test_timeout_handshake():
    r = autotest._interpretar_excepcion(asyncio.TimeoutError(), "host")
    assert r.codigo == "timeout"
    assert "venció" in r.titulo or "tiempo" in r.titulo.lower() or "Railway" in r.sugerencia


def test_tls_invalido():
    r = autotest._interpretar_excepcion(
        ssl.SSLError("CERTIFICATE_VERIFY_FAILED"), "host",
    )
    assert r.codigo == "tls_invalido"
    assert "TLS" in r.titulo or "ca" in r.sugerencia.lower()


def test_sin_ruta_a_host_es_oserror_generico():
    r = autotest._interpretar_excepcion(ConnectionRefusedError("rechazada"), "host")
    assert r.codigo == "sin_ruta_a_host"
    assert "firewall" in r.sugerencia.lower() or "red" in r.sugerencia.lower()


def test_token_invalido_por_cierre_1008():
    from websockets.exceptions import ConnectionClosedError
    from websockets.frames import Close
    # Simula el frame de cierre 1008 (policy violation) que manda el cerebro
    # cuando rechaza el token en el handshake.
    exc = ConnectionClosedError(Close(1008, "policy"), None)
    r = autotest._interpretar_excepcion(exc, "host")
    assert r.codigo == "token_invalido"
    assert "AGENTE_PC_TOKEN" in r.sugerencia


# ── chequear_venv: cuando NO hay .venv no hay falsos positivos ──────────────


def test_chequear_venv_sin_venv_no_falsea(monkeypatch, tmp_path):
    # Apunta `__file__` a una raíz simulada sin .venv → debe devolver None
    # (no es un error: el `uv sync` lo creará).
    raiz = tmp_path / "fake_agente_pc" / "agente_pc"
    raiz.mkdir(parents=True)
    monkeypatch.setattr(daemon, "__file__", str(raiz / "daemon.py"))
    assert daemon.chequear_venv() is None


def test_chequear_venv_roto_apunta_a_python_inexistente(monkeypatch, tmp_path):
    # Simula un .venv con `pyvenv.cfg` que apunta a un Python BASE inexistente:
    # este es el caso que tiraba "access is denied" en Windows.
    raiz_fake = tmp_path / "fake_agente_pc"
    pkg = raiz_fake / "agente_pc"
    pkg.mkdir(parents=True)
    venv = raiz_fake / ".venv"
    (venv / "bin").mkdir(parents=True)
    (venv / "bin" / "python").touch()  # intérprete presente
    (venv / "pyvenv.cfg").write_text(
        "home = " + str(tmp_path / "no_existe_python_312_bin") + "\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(daemon, "__file__", str(pkg / "daemon.py"))
    aviso = daemon.chequear_venv()
    assert aviso is not None
    assert "uv sync" in aviso  # da el comando exacto para regenerarlo


# ── main: enrutado del flag `--test-connection` ─────────────────────────────


def test_main_test_connection_llama_al_autotest(monkeypatch):
    llamado = {"n": 0}

    def fake_ejecutar() -> int:
        llamado["n"] += 1
        return 0

    # `main` chequea que exista `agente_pc/.env` ANTES de enrutar
    # `--test-connection` (devuelve 4 si falta). En CI —y en cualquier máquina
    # sin .env— ese chequeo dispararía y el test mediría el precondition, no el
    # enrutado. Lo damos por satisfecho para aislar la ruta del autotest.
    monkeypatch.setattr(daemon, "chequear_env_file", lambda: None)
    monkeypatch.setattr(daemon.autotest, "ejecutar", fake_ejecutar)
    rc = daemon.main(["--test-connection"])
    assert rc == 0
    assert llamado["n"] == 1


def test_main_help_no_arranca_daemon(monkeypatch):
    # `--help` no debe llamar a cargar_config ni al daemon.
    monkeypatch.setattr(daemon, "cargar_config",
                        lambda: (_ for _ in ()).throw(AssertionError("no arrancar")))
    assert daemon.main(["--help"]) == 0
