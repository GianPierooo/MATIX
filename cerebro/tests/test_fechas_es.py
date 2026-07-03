"""Parser de fechas es-PE (T5): EXHAUSTIVO. Tabla de casos que DEBE resolver +
tabla de casos que DEBE delegar al LLM (None). Regla: si duda, delega."""
from __future__ import annotations

from datetime import datetime, timedelta

import pytest

from app.matix import fechas_es

# jueves 2026-07-02 10:00, hora de Lima (naive). Día del mes = 2.
AHORA = datetime(2026, 7, 2, 10, 0)


def _fecha(dias: int, h: int = 9, m: int = 0) -> datetime:
    d = (AHORA + timedelta(days=dias)).date()
    return datetime(d.year, d.month, d.day, h, m)


def _prox_wd(ahora: datetime, wd: int, skip: bool = False):
    delta = (wd - ahora.weekday()) % 7
    if delta == 0 and skip:
        delta = 7
    return (ahora + timedelta(days=delta)).date()


# ── DEBE resolver (alta confianza) ───────────────────────────────────────────


@pytest.mark.parametrize(
    "texto, esperado",
    [
        ("comprar pan manana", _fecha(1, 9, 0)),          # solo fecha → 09:00
        ("mañana a las 3pm", _fecha(1, 15, 0)),
        ("pasado mañana en la noche", _fecha(2, 20, 0)),
        ("hoy en la noche", _fecha(0, 20, 0)),
        ("hoy al mediodia", _fecha(0, 12, 0)),
        ("en 2 semanas", _fecha(14, 9, 0)),
        ("en 3 dias", _fecha(3, 9, 0)),
        ("recuerdame a las 8pm", _fecha(0, 20, 0)),        # solo hora, futura hoy
        ("a las 15:00", _fecha(0, 15, 0)),
        ("mañana 3 de la tarde", _fecha(1, 15, 0)),
        ("manana en la mañana", _fecha(1, 9, 0)),
        ("hoy 9:30pm", _fecha(0, 21, 30)),
    ],
)
def test_resuelve(texto, esperado):
    r = fechas_es.parsear(texto, AHORA)
    assert r is not None, f"debió resolver: {texto!r}"
    assert r.dt == esperado, (texto, r.dt, esperado)


def test_hora_pasada_hoy_rueda_a_manana():
    # 8am ya pasó (son las 10:00) → es para mañana.
    r = fechas_es.parsear("a las 8am", AHORA)
    assert r is not None and r.dt == _fecha(1, 8, 0)


def test_dia_del_mes_futuro_este_mes():
    r = fechas_es.parsear("pagar la luz el 15", AHORA)  # hoy es 2 → este mes
    assert r is not None and r.dt == datetime(2026, 7, 15, 9, 0)


def test_dia_del_mes_pasado_va_al_siguiente():
    ahora = datetime(2026, 7, 20, 10, 0)  # día 20
    r = fechas_es.parsear("pagar la luz el 15", ahora)  # 15 < 20 → mes siguiente
    assert r is not None and r.dt == datetime(2026, 8, 15, 9, 0)


def test_fecha_con_mes_explicito():
    r = fechas_es.parsear("reunion el 3 de agosto", AHORA)
    assert r is not None and r.dt == datetime(2026, 8, 3, 9, 0)


def test_fin_de_ano_rueda_al_siguiente():
    ahora = datetime(2026, 12, 31, 10, 0)
    r = fechas_es.parsear("comprar utiles el 2", ahora)  # 2 < 31 → enero 2027
    assert r is not None and r.dt == datetime(2027, 1, 2, 9, 0)


def test_dia_de_semana_proxima_ocurrencia():
    r = fechas_es.parsear("el viernes 10am", AHORA)
    d = _prox_wd(AHORA, 4)  # viernes
    assert r is not None and r.dt == datetime(d.year, d.month, d.day, 10, 0)


def test_viernes_cuando_hoy_es_viernes_es_hoy():
    base = datetime(2026, 7, 2, 8, 0)
    vie = base + timedelta(days=(4 - base.weekday()) % 7)  # un viernes 08:00
    ahora_vie = datetime(vie.year, vie.month, vie.day, 8, 0)
    r = fechas_es.parsear("el viernes 3pm", ahora_vie)
    assert r is not None
    assert r.dt.date() == ahora_vie.date()  # HOY mismo, no la próxima semana
    assert r.dt.hour == 15


def test_proximo_viernes_cuando_hoy_es_viernes_salta_semana():
    base = datetime(2026, 7, 2, 8, 0)
    vie = base + timedelta(days=(4 - base.weekday()) % 7)
    ahora_vie = datetime(vie.year, vie.month, vie.day, 8, 0)
    r = fechas_es.parsear("el proximo viernes 10am", ahora_vie)
    assert r is not None and r.dt.date() == (ahora_vie + timedelta(days=7)).date()


def test_texto_limpio_quita_la_fecha():
    r = fechas_es.parsear("comprar pan mañana a las 3pm", AHORA)
    assert r is not None
    assert "manana" not in fechas_es._norm(r.texto_limpio)
    assert "3pm" not in fechas_es._norm(r.texto_limpio)
    assert "pan" in r.texto_limpio.lower()


# ── DEBE delegar al LLM (None) ───────────────────────────────────────────────


@pytest.mark.parametrize(
    "texto",
    [
        "a las 3",                       # hora sin am/pm ni franja → ambigua
        "recuerdame algo mas tarde",
        "nos vemos el finde",
        "hablamos la proxima",
        "todos los lunes revisar correo",
        "cada mañana meditar",
        "esta semana avanzar la tesis",
        "comprar pan",                   # sin fecha
        "llamar al banco pronto",
        "en la madrugada",
        "cuando pueda paso por ahi",
        "reunion en un rato",
    ],
)
def test_delega_al_llm(texto):
    assert fechas_es.parsear(texto, AHORA) is None, f"debió delegar: {texto!r}"


def test_texto_vacio_delega():
    assert fechas_es.parsear("", AHORA) is None
    assert fechas_es.parsear("   ", AHORA) is None


@pytest.mark.parametrize(
    "texto",
    [
        # DOS o más fechas/horas → NUNCA elegir la primera en silencio (P0).
        "el lunes o el martes",
        "el lunes o el martes 3pm",
        "a las 3pm o a las 5pm",
        "manana o pasado manana",
        "el 15 o el 20",
        "el lunes y el martes",
        "hoy o manana",
        "reunion a las 3pm y a las 6pm",
        "manana y el viernes",
        # Hora con meridiano fuera de 1-12 = basura → delega (P0).
        "a las 99pm",
        "a las 13pm",
    ],
)
def test_multiples_o_invalidas_delegan(texto):
    assert fechas_es.parsear(texto, AHORA) is None, texto


@pytest.mark.parametrize(
    "texto",
    [
        # Disyunciones y cross-type con fechas completas.
        "el 3 de enero o el 5 de enero",
        "a las 10 o a las 11 de la manana",
        "manana temprano o el jueves",
        "el lunes 3pm o manana",
        "hoy a las 3pm y manana a las 4pm",
        "el 15 a las 3pm o a las 5pm",   # una fecha, DOS horas
        "manana o",                       # disyunción colgante
        # Horas/fechas inválidas → nunca inventar.
        "a las 0am",                      # 0 no es 1-12
        "el 00",                          # día 0
        "el 31 de febrero",               # fecha imposible
        "a la medianoche",                # no reconocida → delega
    ],
)
def test_adversarios_extra_delegan(texto):
    assert fechas_es.parsear(texto, AHORA) is None, texto


def test_bordes_de_mes_y_anio():
    # "el 31 de diciembre" el 15-dic → este año; "el 1 de enero" → el que viene.
    r = fechas_es.parsear("el 31 de diciembre", datetime(2026, 12, 15, 10, 0))
    assert r is not None and r.dt == datetime(2026, 12, 31, 9, 0)
    r = fechas_es.parsear("el 1 de enero", datetime(2026, 12, 15, 10, 0))
    assert r is not None and r.dt == datetime(2027, 1, 1, 9, 0)
    # 2026 NO es bisiesto → 29 de febrero es imposible → delega (no inventa).
    assert fechas_es.parsear("el 29 de febrero", datetime(2026, 1, 10, 10, 0)) is None


def test_docena_meridiano():
    # 12pm = mediodía (12:00); 12am = medianoche (00:00, rueda a mañana si pasó).
    r = fechas_es.parsear("a las 12pm", AHORA)
    assert r is not None and r.dt.hour == 12 and r.dt.minute == 0
    r = fechas_es.parsear("a las 12am", AHORA)
    assert r is not None and r.dt.hour == 0


@pytest.mark.parametrize(
    "texto, esperado",
    [
        ("a las 3", True),        # cue ambiguo (hora sin am/pm)
        ("mañana", True),
        ("el 15", True),
        ("mas tarde", True),
        ("cada lunes", True),
        ("comprar pan", False),
        ("llamar a mama", False),
        ("revisar el correo", False),
    ],
)
def test_hay_senal_de_fecha(texto, esperado):
    assert fechas_es.hay_senal_de_fecha(texto) is esperado
