"""Muestras de voz del wake word (módulo puro + zip, sin red).

La subida/descarga real va contra Supabase Storage; aquí monkeypatcheamos
`listar` y `_descargar` para probar el empaquetado y los helpers de nombre.
"""
from __future__ import annotations

import io
import zipfile

import pytest

from app.matix import muestras_voz as mv


def test_nombre_objeto_acolcha_indice():
    assert mv.nombre_objeto("positivo", 7) == "positivo-007.wav"
    assert mv.nombre_objeto("negativo", 123) == "negativo-123.wav"


def test_nombre_objeto_tipo_invalido():
    with pytest.raises(ValueError):
        mv.nombre_objeto("otro", 1)


def test_arcname_reagrupa_por_tipo():
    assert mv._arcname("positivo-007.wav") == "positivo/007.wav"
    assert mv._arcname("negativo-001.wav") == "negativo/001.wav"
    # Un nombre inesperado se conserva tal cual (no rompe el zip).
    assert mv._arcname("raro.wav") == "raro.wav"


@pytest.mark.asyncio
async def test_conteo_separa_positivos_y_negativos(monkeypatch):
    async def fake_listar():
        return [
            "positivo-001.wav",
            "positivo-002.wav",
            "negativo-001.wav",
        ]

    monkeypatch.setattr(mv, "listar", fake_listar)
    c = await mv.conteo()
    assert c == {"positivo": 2, "negativo": 1, "total": 3}


@pytest.mark.asyncio
async def test_zip_todos_agrupa_en_carpetas(monkeypatch):
    async def fake_listar():
        return ["positivo-001.wav", "negativo-001.wav"]

    async def fake_descargar(obj):
        return f"datos-{obj}".encode()

    monkeypatch.setattr(mv, "listar", fake_listar)
    monkeypatch.setattr(mv, "_descargar", fake_descargar)

    datos = await mv.zip_todos()
    with zipfile.ZipFile(io.BytesIO(datos)) as zf:
        nombres = sorted(zf.namelist())
        assert nombres == ["negativo/001.wav", "positivo/001.wav"]
        assert zf.read("positivo/001.wav") == b"datos-positivo-001.wav"
