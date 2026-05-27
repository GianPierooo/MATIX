"""Filtro de alucinaciones de Whisper en `llm.py`."""
from __future__ import annotations

from app.matix.llm import _es_alucinacion_de_whisper


def test_amara_exacto() -> None:
    assert _es_alucinacion_de_whisper(
        "Subtítulos realizados por la comunidad de Amara.org"
    )


def test_amara_con_puntuacion() -> None:
    assert _es_alucinacion_de_whisper(
        "  Subtítulos realizados por la comunidad de Amara.org. "
    )


def test_amara_repetido() -> None:
    # Whisper a veces repite la misma frase. Si la sacamos, queda
    # vacío → es alucinación.
    txt = (
        "Subtítulos realizados por la comunidad de Amara.org "
        "Subtítulos realizados por la comunidad de Amara.org"
    )
    assert _es_alucinacion_de_whisper(txt)


def test_solo_musica() -> None:
    assert _es_alucinacion_de_whisper("[Música]")
    assert _es_alucinacion_de_whisper("(música)")
    assert _es_alucinacion_de_whisper("♪")


def test_solo_signos() -> None:
    assert _es_alucinacion_de_whisper("...")
    assert _es_alucinacion_de_whisper("!! ¡¿?")


def test_frases_legitimas_no_son_alucinacion() -> None:
    # Casos reales del usuario que NO deben filtrarse.
    assert not _es_alucinacion_de_whisper(
        "Anotame una tarea para mañana a las ocho"
    )
    assert not _es_alucinacion_de_whisper("Sí")
    assert not _es_alucinacion_de_whisper("No")
    assert not _es_alucinacion_de_whisper("¿Qué tengo hoy?")
    # Una frase que MENCIONA la alucinación pero tiene más contenido
    # debería pasar (es algo que el usuario dijo, no la alucinación
    # sola).
    assert not _es_alucinacion_de_whisper(
        "Anota que vi un video con subtítulos de Amara.org sobre Whisper"
    )


def test_vacio() -> None:
    assert not _es_alucinacion_de_whisper("")
