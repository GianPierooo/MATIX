"""Tests del módulo de modos de Matix (file-driven, sin BD).

La carga de los `.md`, la metadata y el envoltorio son lógica pura. El
get/set del modo activo (config_matix) se prueba indirectamente vía el
dispatcher de tools y a mano contra prod.
"""
from __future__ import annotations

from app.matix import modos


def test_listar_modos_file_driven() -> None:
    nombres = {m["nombre"] for m in modos.listar_modos()}
    # Los 3 iniciales existen como .md en el repo.
    assert {"tesis", "estudio", "motivacion"} <= nombres


def test_meta_se_lee_del_md() -> None:
    meta = modos.meta_modo("tesis")
    assert meta is not None
    assert meta["nombre"] == "tesis"
    assert meta["etiqueta"] == "Tesis"
    assert meta["descripcion"]  # la línea `> ...`


def test_existe_y_carga() -> None:
    assert modos.existe_modo("estudio") is True
    assert modos.existe_modo("inexistente") is False
    assert modos.existe_modo("") is False
    assert modos.existe_modo(None) is False
    assert modos.cargar_modo("inexistente") is None
    assert modos.cargar_modo("estudio")


def test_anti_traversal() -> None:
    # No debe poder salir de la carpeta de modos.
    assert modos.existe_modo("../tools") is False
    assert modos.existe_modo("../../config") is False


def test_envoltura_recuerda_que_reglas_base_mandan() -> None:
    contenido = modos.cargar_modo("tesis")
    assert contenido is not None
    env = modos.envoltura_modo("tesis", contenido)
    assert env.startswith("MODO ACTIVO: Tesis")
    assert "reglas base" in env
    # El .md completo va dentro del envoltorio.
    assert contenido in env


def test_tesis_incluye_guia_humanizer() -> None:
    contenido = modos.cargar_modo("tesis")
    assert contenido is not None
    bajo = contenido.lower()
    assert "marcas de ia" in bajo or "evitar" in bajo
    assert "voz activa" in bajo
