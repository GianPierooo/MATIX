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


def test_extraer_completo_no_capea():
    # extraer() capa a MAX_CHARS; extraer_completo() devuelve TODO (para
    # resumir por troceo).
    grande = ("linea de relleno\n" * 4000)
    completo = ed.extraer_completo("largo.md", grande.encode())
    assert len(completo) > ed.MAX_CHARS
    assert completo == grande.strip()


def test_trocear_parte_sin_romper_frases():
    texto = "\n".join(f"oracion numero {i}." for i in range(500))
    trozos = ed.trocear(texto, 1000)
    assert len(trozos) >= 2
    # Reconstruye el contenido (sin perder ni duplicar palabras clave).
    assert sum(t.count("oracion") for t in trozos) == 500
    # Ningún trozo vacío.
    assert all(t.strip() for t in trozos)


def test_trocear_texto_corto_un_solo_trozo():
    assert ed.trocear("hola mundo", 1000) == ["hola mundo"]
    assert ed.trocear("", 1000) == []


def test_extension_no_soportada_lanza():
    with pytest.raises(ed.DocumentoNoSoportado):
        ed.extraer("foto.png", b"\x89PNG")
    with pytest.raises(ed.DocumentoNoSoportado):
        ed.extraer_completo("foto.png", b"\x89PNG")


def test_sin_extension_lanza():
    with pytest.raises(ed.DocumentoNoSoportado):
        ed.extraer("archivo_sin_ext", b"data")
