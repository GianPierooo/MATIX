"""Tests del pulido de personalidad / flujo del chat (prompt + temporal).

No probamos el modelo (no-determinista); sí que el prompt base lleva las
piezas pedidas y que la hora de Lima se formatea en español.
"""
from __future__ import annotations

from app.matix.chat import _ahora_lima_es
from app.matix.system_prompt import system_prompt_fijo

_DIAS = ("lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo")


def test_ahora_lima_es_formato_espanol_12h() -> None:
    s = _ahora_lima_es()
    assert any(d in s for d in _DIAS), s
    assert ("a. m." in s) or ("p. m." in s), s
    assert " de " in s  # "… de febrero de 2026"


def test_prompt_base_tiene_personalidad_y_sesgo_y_temporal() -> None:
    p = system_prompt_fijo()
    for marca in (
        "PERSONALIDAD",
        "SESGO A LA ACCIÓN",
        "CONCIENCIA TEMPORAL",
        "ENSEÑAR DE VERDAD",
        "FORMATO DE SALIDA",
    ):
        assert marca in p, marca
    # El caso concreto a corregir está cubierto en el prompt.
    assert "activa otro modo" in p


def test_prompt_no_modela_asteriscos_en_ejemplos_de_salida() -> None:
    p = system_prompt_fijo()
    # Los ejemplos de OUTPUT ya no llevan negrita markdown.
    assert "**Resumen de" not in p
    assert "**Lo que dice tu apunte:**" not in p
