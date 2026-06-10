"""Chequeos accionables del arranque del daemon: cuando algo está mal, el
mensaje debe decir QUÉ está mal Y QUÉ COMANDO ejecutar.

Probamos:
- `chequear_env_file`: sin .env devuelve mensaje con `cp` exacto.
- `diagnosticar_token`: distingue token vacío vs con espacios vs muy corto;
  cada caso da una pista accionable distinta.

Todos PUROS (sin tocar el FS real para los casos de token; para .env hacemos
patching de RUTA_ENV con tmp_path).
"""
from __future__ import annotations

from pathlib import Path

from agente_pc import daemon
from agente_pc.config import ConfigAgente


def _cfg(token: str = "") -> ConfigAgente:
    return ConfigAgente(
        agente_pc_token=token,
        cerebro_ws_url="wss://example.test/api/v1/agente/ws",
        host_esperado="example.test",
        agente_pc_allowlist="",
    )


def test_env_ausente_da_mensaje_con_cp_exacto(monkeypatch, tmp_path: Path) -> None:
    ruta_inexistente = tmp_path / ".env"  # no la creamos
    monkeypatch.setattr(daemon, "RUTA_ENV", ruta_inexistente)
    msg = daemon.chequear_env_file()
    assert msg is not None
    # El mensaje debe mencionar el comando `cp` y la plantilla `.env.example`.
    assert "cp " in msg
    assert ".env.example" in msg
    # Y debe mencionar AGENTE_PC_TOKEN para que el usuario sepa qué rellenar.
    assert "AGENTE_PC_TOKEN" in msg


def test_env_presente_no_avisa(monkeypatch, tmp_path: Path) -> None:
    ruta = tmp_path / ".env"
    ruta.write_text("AGENTE_PC_TOKEN=algo\n", encoding="utf-8")
    monkeypatch.setattr(daemon, "RUTA_ENV", ruta)
    assert daemon.chequear_env_file() is None


def test_token_vacio_da_mensaje_accionable() -> None:
    msg = daemon.diagnosticar_token(_cfg(token=""))
    assert msg is not None
    assert "AGENTE_PC_TOKEN" in msg
    assert "Railway" in msg
    # Sugiere cómo generar uno.
    assert "secrets.token_urlsafe" in msg


def test_token_con_espacios_lo_detecta() -> None:
    msg = daemon.diagnosticar_token(_cfg(token="  abc1234567890123456789012345  "))
    assert msg is not None
    # Mensaje específico: "espacios o saltos de línea al borde".
    assert "espacios" in msg.lower() or "saltos" in msg.lower()
    # Da pista de cómo se ve el correcto.
    assert "AGENTE_PC_TOKEN=" in msg


def test_token_muy_corto_lo_detecta() -> None:
    msg = daemon.diagnosticar_token(_cfg(token="corto"))
    assert msg is not None
    assert "corto" in msg.lower() or "placeholder" in msg.lower()
    assert "Railway" in msg


def test_token_largo_y_limpio_no_avisa() -> None:
    # Token URLsafe de 48 bytes ~= 64 chars, sin espacios.
    tok = "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789AbCdEfGhIjKlMnOpQrStUvWxYzABCD"
    assert daemon.diagnosticar_token(_cfg(token=tok)) is None


# ── log en archivo (observabilidad del autostart sin consola) ───────────────


def test_agregar_log_archivo_idempotente_y_escribe(monkeypatch, tmp_path: Path) -> None:
    """`_agregar_log_archivo` deja UN solo RotatingFileHandler (idempotente) y
    crea el archivo en `agente_pc/agente_runtime.log`. Apuntamos `__file__` a una
    raíz simulada para no tocar el árbol real."""
    import logging
    from logging.handlers import RotatingFileHandler

    pkg = tmp_path / "agente_pc"
    pkg.mkdir()
    # parents[1] de pkg/daemon.py == tmp_path → el log cae en tmp_path.
    monkeypatch.setattr(daemon, "__file__", str(pkg / "daemon.py"))

    log = logging.getLogger("matix.agente.test_filelog")
    log.handlers.clear()
    daemon._agregar_log_archivo(log)
    daemon._agregar_log_archivo(log)  # segunda vez: NO duplica

    fhs = [h for h in log.handlers if isinstance(h, RotatingFileHandler)]
    try:
        assert len(fhs) == 1
        assert (tmp_path / "agente_runtime.log").exists()
    finally:
        # Cierra el handler: en Windows un archivo abierto bloquea el tmp_path.
        for h in fhs:
            h.close()
            log.removeHandler(h)


# ── instancia única (guard anti-duplicados del autostart) ───────────────────


def test_instancia_unica_en_no_windows_no_bloquea(monkeypatch) -> None:
    """Fuera de Windows el guard NO aplica (el autostart es de Windows): debe
    devolver False sin tocar ctypes — así el daemon y el CI en Linux nunca se
    bloquean por este chequeo."""
    monkeypatch.setattr(daemon.os, "name", "posix")
    assert daemon._ya_hay_otra_instancia() is False
