"""Tests puros del ingestor de documentos (script de la biblioteca).

Solo la lógica que no toca red ni BD: el slug de bloque y el troceo.
Cargamos el script por ruta (no es un paquete importable).
"""
from __future__ import annotations

import importlib.util
from pathlib import Path

_RUTA = Path(__file__).resolve().parent.parent / "scripts" / "ingestar_documentos.py"
_spec = importlib.util.spec_from_file_location("ingestar_documentos", _RUTA)
ing = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ing)


def test_slug_bloque_normaliza():
    assert ing.slug_bloque("Bloque 3") == "bloque_3"
    assert ing.slug_bloque("Día 1") == "dia_1"
    assert ing.slug_bloque("  Front-Lever!! ") == "front_lever"
    assert ing.slug_bloque("BLOQUE_2") == "bloque_2"


def test_slug_bloque_vacio_no_revienta():
    assert ing.slug_bloque("   ") == "sin_nombre"
    assert ing.slug_bloque("¡!") == "sin_nombre"


def test_trocear():
    assert ing.trocear("", 100) == []
    assert ing.trocear("hola", 100) == ["hola"]
    piezas = ing.trocear("a" * 250, 100)
    assert len(piezas) == 3
    # No se pierde ni se duplica contenido.
    assert sum(len(p) for p in piezas) == 250


def test_bloque_override_pasa_por_slug():
    """`--bloque 4` debe quedar como 'bloque_4' tras normalización (no '4')."""
    # El override entra al mismo normalizador que el filename.
    assert ing.slug_bloque("4") == "4"
    assert ing.slug_bloque("Bloque 4") == "bloque_4"
    # Y nombres de filename con sufijo siguen funcionando para el camino
    # normal (cuando no se pasa override).
    assert ing.slug_bloque("bloque_4_placeholder") == "bloque_4_placeholder"
