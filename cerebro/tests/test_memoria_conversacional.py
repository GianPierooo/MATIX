"""Lógica pura de la memoria conversacional: chunking, fecha en palabras y
armado del resultado con fecha. Sin BD ni red."""
from __future__ import annotations

from datetime import datetime, timezone

from app.matix import memoria_conversacional as mc


def _dt(y, m, d, h=12):
    return datetime(y, m, d, h, 0, tzinfo=timezone.utc)


def test_chunking_agrupa_intercambio_en_un_chunk():
    msgs = [
        {"rol": "user", "contenido": "¿qué es una derivada?", "creado_en": _dt(2026, 6, 1)},
        {"rol": "assistant", "contenido": "La tasa de cambio instantánea.", "creado_en": _dt(2026, 6, 1)},
    ]
    chunks = mc.construir_chunks(msgs)
    assert len(chunks) == 1
    assert chunks[0]["n_mensajes"] == 2
    assert "Usuario: ¿qué es una derivada?" in chunks[0]["contenido"]
    assert "Matix: La tasa de cambio instantánea." in chunks[0]["contenido"]
    assert chunks[0]["fecha"] == _dt(2026, 6, 1)  # fecha del primer mensaje


def test_chunking_parte_por_presupuesto_de_caracteres():
    largo = "x" * 800
    msgs = [
        {"rol": "user", "contenido": largo, "creado_en": _dt(2026, 6, 1)},
        {"rol": "assistant", "contenido": largo, "creado_en": _dt(2026, 6, 1)},
        {"rol": "user", "contenido": largo, "creado_en": _dt(2026, 6, 2)},
    ]
    chunks = mc.construir_chunks(msgs, max_chars=1000)
    # No entra todo en un solo chunk de 1000 chars → se parte.
    assert len(chunks) >= 2


def test_chunking_ignora_vacios():
    msgs = [
        {"rol": "user", "contenido": "  ", "creado_en": _dt(2026, 6, 1)},
        {"rol": "assistant", "contenido": "hola", "creado_en": _dt(2026, 6, 1)},
    ]
    chunks = mc.construir_chunks(msgs)
    assert len(chunks) == 1 and chunks[0]["n_mensajes"] == 1


def test_describir_fecha_hoy_ayer_y_pasado():
    ahora = _dt(2026, 6, 10, 15)
    assert mc.describir_fecha(_dt(2026, 6, 10, 9), ahora=ahora) == "hoy"
    assert mc.describir_fecha(_dt(2026, 6, 9, 9), ahora=ahora) == "ayer"
    texto = mc.describir_fecha(_dt(2026, 6, 3, 9), ahora=ahora)
    assert "hace" in texto and "junio" in texto


def test_formatear_recuerdos_pone_fecha_texto():
    ahora = _dt(2026, 6, 10, 15)
    filas = [
        {"contenido": "hablamos de la tesis", "fecha": "2026-06-09T12:00:00+00:00", "distancia": 0.21},
    ]
    out = mc.formatear_recuerdos(filas, ahora=ahora)
    assert out[0]["contenido"] == "hablamos de la tesis"
    assert out[0]["fecha_texto"] == "ayer"
    assert out[0]["distancia"] == 0.21


def test_parse_dt_acepta_z_y_offset():
    assert mc._parse_dt("2026-06-09T12:00:00Z") is not None
    assert mc._parse_dt("2026-06-09T12:00:00+00:00") is not None
    assert mc._parse_dt(None) is None
    assert mc._parse_dt("basura") is None
