"""Rails de seguridad: allowlist / denylist / ocultamiento de secretos.

Estos tests son el límite de seguridad del agente. Cubren explícitamente los
casos que DEBEN rechazarse. Usan el fixture `area` (bajo el home, no bajo
AppData) para que la denylist de sistema no enmascare la lógica de allowlist.
"""
from __future__ import annotations

import os

from agente_pc.seguridad import entrada_oculta, ruta_permitida


def test_acepta_dentro_de_allowlist(area):
    sub = area / "proyectos"
    sub.mkdir()
    v = ruta_permitida(str(sub), [area])
    assert v.permitida is True


def test_acepta_la_propia_raiz_de_allowlist(area):
    v = ruta_permitida(str(area), [area])
    assert v.permitida is True


def test_rechaza_fuera_de_allowlist(area):
    sub = area / "permitida"
    sub.mkdir()
    # El padre de la carpeta permitida NO está permitido.
    v = ruta_permitida(str(area), [sub])
    assert v.permitida is False
    assert v.motivo == "fuera de la allowlist"


def test_denylist_nombre_gana_sobre_allowlist(area):
    # .ssh DENTRO de una carpeta permitida igual se rechaza.
    ssh = area / ".ssh"
    ssh.mkdir()
    v = ruta_permitida(str(ssh), [area])
    assert v.permitida is False
    assert v.motivo == "componente prohibido"


def test_denylist_env_gana_sobre_allowlist(area):
    env = area / ".env"
    env.mkdir()
    v = ruta_permitida(str(env), [area])
    assert v.permitida is False
    assert v.motivo == "componente prohibido"


def test_rechaza_raiz_de_sistema_aunque_este_en_allowlist():
    # /etc en POSIX, C:\Windows en Windows. La denylist de sistema gana incluso
    # si la metes a mano en la allowlist.
    objetivo = r"C:\Windows" if os.name == "nt" else "/etc"
    v = ruta_permitida(objetivo, [objetivo])
    assert v.permitida is False
    assert v.motivo == "carpeta de sistema"


def test_rechaza_escape_con_dotdot(area):
    sub = area / "permitida"
    sub.mkdir()
    # 'permitida/../..' resuelve FUERA de la allowlist.
    escape = os.path.join(str(sub), "..", "..")
    v = ruta_permitida(escape, [sub])
    assert v.permitida is False


def test_rechaza_ruta_vacia(area):
    assert ruta_permitida("", [area]).permitida is False
    assert ruta_permitida("   ", [area]).permitida is False


def test_allowlist_vacia_rechaza_todo(area):
    assert ruta_permitida(str(area), []).permitida is False


def test_entrada_oculta_secretos():
    secretos = [
        ".env",
        ".env.local",
        ".ssh",
        "id_rsa",
        "id_ed25519",
        "server.pem",
        "clave.key",
        "store.pfx",
        "credentials",
        "secrets",
        "appdata",
    ]
    for n in secretos:
        assert entrada_oculta(n) is True, n


def test_entrada_visible_normal():
    for n in ["tarea.txt", "foto.png", "Proyectos", "notas.md", "informe.docx"]:
        assert entrada_oculta(n) is False, n


def test_symlink_que_escapa_se_rechaza(area, tmp_path):
    """Un symlink DENTRO de la allowlist que apunta FUERA debe rechazarse: la
    ruta se resuelve (realpath) antes de validar, así que el destino real cae
    fuera de la allowlist."""
    import pytest

    fuera = area.parent / "fuera_objetivo"
    fuera.mkdir(exist_ok=True)
    (fuera / "secreto.txt").write_text("clave", encoding="utf-8")
    enlace = area / "atajo"
    try:
        os.symlink(fuera, enlace, target_is_directory=True)
    except (OSError, NotImplementedError):
        pytest.skip("este sistema no permite crear symlinks sin privilegios")
    try:
        # El symlink está dentro de `area`, pero resuelve fuera → rechazado.
        v = ruta_permitida(str(enlace / "secreto.txt"), [area])
        assert v.permitida is False
    finally:
        try:
            enlace.unlink()
        except OSError:
            pass
