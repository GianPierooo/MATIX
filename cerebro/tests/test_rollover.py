"""Lógica pura del rollover de tareas no cumplidas (Capa 8): detección de lo no
cumplido, búsqueda de huecos libres multi-día, colocación secuencial sin pisarse
y el umbral honesto de sobrecarga. Sin BD ni FCM."""
from __future__ import annotations

from datetime import datetime, timezone

from app.matix import rollover as r


def _utc(y, mo, d, h=0, mi=0):
    return datetime(y, mo, d, h, mi, tzinfo=timezone.utc)


# ── Detección de lo no cumplido ──────────────────────────────────────────────

def test_tareas_no_cumplidas_detecta_pasadas_y_ordena():
    ahora = _utc(2026, 6, 5, 18, 0)
    tareas = [
        {"id": "a", "titulo": "vieja", "vence_en": "2026-06-04T10:00:00Z"},
        {"id": "b", "titulo": "hoy temprano", "bloque_fin": "2026-06-05T09:00:00Z"},
        {"id": "c", "titulo": "futura", "vence_en": "2026-06-06T10:00:00Z"},
        {"id": "d", "titulo": "ok", "vence_en": "2026-06-01T10:00:00Z", "completada": True},
        {"id": "e", "titulo": "trash", "vence_en": "2026-06-01T10:00:00Z",
         "eliminado_en": "2026-06-02T00:00:00Z"},
        {"id": "f", "titulo": "sin plazo"},
    ]
    out = r.tareas_no_cumplidas(tareas, ahora)
    # Solo las pasadas y vivas, lo más viejo primero.
    assert [t["id"] for t in out] == ["a", "b"]


def test_plazo_efectivo_prefiere_bloque_sobre_vence():
    t = {"bloque_fin": "2026-06-10T09:00:00Z", "vence_en": "2026-06-01T09:00:00Z"}
    assert r.plazo_efectivo(t) == _utc(2026, 6, 10, 9, 0)


# ── Búsqueda de huecos libres (multi-día) ────────────────────────────────────

def test_buscar_hueco_primer_fit_en_orden_de_dia_y_hora():
    ventanas = [
        (0, [{"ini": 600, "fin": 620, "dur": 20}]),  # hoy solo 20 min
        (1, [{"ini": 540, "fin": 600, "dur": 60},
             {"ini": 700, "fin": 760, "dur": 60}]),
    ]
    # 30 min no cabe hoy (20<30) → primer hueco de mañana a las 09:00.
    assert r.buscar_hueco(ventanas, 30) == {"offset": 1, "ini": 540, "fin": 570}


def test_buscar_hueco_none_si_no_cabe_en_ningun_dia():
    ventanas = [(0, [{"ini": 600, "fin": 610, "dur": 10}])]
    assert r.buscar_hueco(ventanas, 30) is None


# ── Colocación secuencial (sin pisarse) ──────────────────────────────────────

def test_colocar_secuencial_no_pisa_y_no_muta_entrada():
    ventanas = [(0, [{"ini": 540, "fin": 720, "dur": 180}])]  # 3h hoy
    out = r.colocar_secuencial(ventanas, [60, 60], buffer_min=10)
    assert out[0]["ini"] == 540
    assert out[1]["ini"] == 540 + 60 + 10  # 610, tras buffer
    # No muta la entrada original.
    assert ventanas[0][1][0]["ini"] == 540


def test_colocar_secuencial_segundo_rueda_al_dia_siguiente():
    ventanas = [
        (0, [{"ini": 540, "fin": 600, "dur": 60}]),   # solo 1 bloque hoy
        (1, [{"ini": 540, "fin": 660, "dur": 120}]),
    ]
    out = r.colocar_secuencial(ventanas, [60, 60], buffer_min=10)
    assert out[0]["offset"] == 0
    assert out[1]["offset"] == 1  # el segundo no cupo hoy → mañana


# ── Guardrail honesto de sobrecarga ──────────────────────────────────────────

def test_sobrecarga_por_repeticiones():
    s = r.evaluar_sobrecarga([{"titulo": "informe", "veces_reprogramada": 3}])
    assert s["sobrecargado"] is True
    assert s["recomendacion"] == "reescopar"
    assert "3 veces" in s["mensaje"]
    assert "*" not in s["mensaje"]


def test_sobrecarga_por_cantidad():
    arr = [{"titulo": f"t{i}", "veces_reprogramada": 0} for i in range(5)]
    s = r.evaluar_sobrecarga(arr)
    assert s["sobrecargado"] is True
    assert s["recomendacion"] == "bajar_carga"
    assert s["n"] == 5


def test_sobrecarga_normal_no_dispara():
    s = r.evaluar_sobrecarga([
        {"titulo": "x", "veces_reprogramada": 1},
        {"titulo": "y", "veces_reprogramada": 0},
    ])
    assert s["sobrecargado"] is False
    assert s["mensaje"] is None
    assert s["recomendacion"] is None


def test_sobrecarga_vacia():
    s = r.evaluar_sobrecarga([])
    assert s["sobrecargado"] is False
    assert s["n"] == 0


def test_umbral_configurable():
    arr = [{"titulo": "x", "veces_reprogramada": 2}]
    assert r.evaluar_sobrecarga(arr, umbral_repeticiones=2)["sobrecargado"] is True
    assert r.evaluar_sobrecarga(arr, umbral_repeticiones=5)["sobrecargado"] is False


# ── Textos (español, sin asteriscos) ─────────────────────────────────────────

def test_texto_aviso_usa_mensaje_honesto_si_sobrecarga():
    sob = {"sobrecargado": True, "mensaje": "toca achicarlo o soltarlo"}
    tt, cuerpo = r.texto_aviso_rollover(4, sob)
    assert cuerpo == "toca achicarlo o soltarlo"
    assert "*" not in tt and "*" not in cuerpo


def test_texto_aviso_singular_y_plural():
    sob = {"sobrecargado": False}
    assert "algo" in r.texto_aviso_rollover(1, sob)[0].lower()
    assert "3" in r.texto_aviso_rollover(3, sob)[0]


def test_cuando_humano_hoy_manana_y_dia():
    local = datetime(2026, 6, 5, 12, 0, tzinfo=r.LIMA)  # viernes
    assert r.cuando_humano(local, 0, 600) == "hoy 10:00"
    assert r.cuando_humano(local, 1, 540) == "mañana 09:00"
    txt = r.cuando_humano(local, 3, 600)  # +3 días → lunes
    assert "lun" in txt and "10:00" in txt
