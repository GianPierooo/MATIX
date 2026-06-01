"""Extracción de texto de documentos adjuntos al chat (módulo puro)."""
from __future__ import annotations

import pytest

from app.matix import extraccion_documentos as ed


def test_txt_se_extrae_sin_truncar():
    texto, trunc = ed.extraer("notas.txt", b"Hola Matix\nprueba")
    assert "Hola Matix" in texto
    assert trunc is False


def test_md_se_acepta():
    texto, _ = ed.extraer("apunte.md", b"# Titulo\ncontenido")
    assert "Titulo" in texto


def test_documento_largo_se_capea_y_marca_truncado():
    grande = ("linea de relleno\n" * 4000).encode()  # > MAX_CHARS
    texto, trunc = ed.extraer("largo.md", grande)
    assert trunc is True
    assert len(texto) <= ed.MAX_CHARS


def test_extension_no_soportada_lanza():
    with pytest.raises(ed.DocumentoNoSoportado):
        ed.extraer("foto.png", b"\x89PNG")


def test_sin_extension_lanza():
    with pytest.raises(ed.DocumentoNoSoportado):
        ed.extraer("archivo_sin_ext", b"data")
