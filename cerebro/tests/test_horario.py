"""Lógica pura de la capa de horario: expansión de recurrencia, ventanas libres,
colocación (regla del pico, buffers, recorte por capacidad). Sin BD."""
from __future__ import annotations

from datetime import date

from app.matix import horario as h

# Atajos en minutos.
DESPERTAR = 7 * 60   # 420
DORMIR = 23 * 60     # 1380
PICO_INI = 6 * 60    # 360
PICO_FIN = 9 * 60    # 540


def test_hhmm_roundtrip():
    assert h.hhmm_a_min("07:30") == 450
    assert h.min_a_hhmm(450) == "07:30"
    assert h.hhmm_a_min("nope") is None


def test_ocurre_en_suelto_diaria_semanal_hasta():
    # Evento suelto: solo su fecha.
    suelto = {"inicia_en": "2026-06-04T09:00:00-05:00"}
    assert h.ocurre_en(suelto, date(2026, 6, 4)) is True
    assert h.ocurre_en(suelto, date(2026, 6, 5)) is False

    # Diaria desde el 1: cae cualquier día >= inicio, no antes.
    diaria = {"inicia_en": "2026-06-01T06:00:00-05:00",
              "recurrencia_freq": "diaria", "recurrencia_fin_tipo": "nunca"}
    assert h.ocurre_en(diaria, date(2026, 6, 5)) is True
    assert h.ocurre_en(diaria, date(2026, 5, 30)) is False

    # Semanal: solo el mismo día de la semana que arranca.
    start = date(2026, 6, 1)
    semanal = {"inicia_en": "2026-06-01T17:00:00-05:00", "recurrencia_freq": "semanal",
               "recurrencia_dias_semana": [start.isoweekday()], "recurrencia_fin_tipo": "nunca"}
    assert h.ocurre_en(semanal, date(2026, 6, 8)) is True   # +7 días, mismo weekday
    assert h.ocurre_en(semanal, date(2026, 6, 2)) is False  # día siguiente, otro weekday

    # Fin 'hasta': no pasa de la fecha tope.
    hasta = {"inicia_en": "2026-06-01T06:00:00-05:00", "recurrencia_freq": "diaria",
             "recurrencia_fin_tipo": "hasta", "recurrencia_hasta": "2026-06-03"}
    assert h.ocurre_en(hasta, date(2026, 6, 3)) is True
    assert h.ocurre_en(hasta, date(2026, 6, 4)) is False


def test_ventanas_libres_resta_lo_fijo_con_buffer_y_respeta_limites():
    # Una clase 8:00-10:00, buffer 10 → ocupa 7:50-10:10.
    fijos = [{"ini_min": 480, "fin_min": 600, "titulo": "Clase", "tipo": "clase"}]
    v = h.ventanas_libres(fijos, despertar_min=DESPERTAR, dormir_min=DORMIR, buffer_min=10)
    # Ventanas: [7:00,7:50] y [10:10,23:00].
    assert v[0] == {"ini": 420, "fin": 470, "dur": 50}
    assert v[1] == {"ini": 610, "fin": 1380, "dur": 770}
    # Nada pasa de la hora de dormir.
    assert all(w["fin"] <= DORMIR for w in v)


def test_ventanas_libres_desde_ahora_recorta_lo_pasado():
    v = h.ventanas_libres([], despertar_min=DESPERTAR, dormir_min=DORMIR,
                          buffer_min=10, desde_min=15 * 60)  # 15:00
    assert v == [{"ini": 900, "fin": 1380, "dur": 480}]
    # Si ya pasó la hora de dormir, no hay ventanas.
    assert h.ventanas_libres([], despertar_min=DESPERTAR, dormir_min=DORMIR,
                             buffer_min=10, desde_min=23 * 60 + 30) == []


def test_es_pico():
    assert h.es_pico({"ini": 420, "fin": 540}, PICO_INI, PICO_FIN) is True
    assert h.es_pico({"ini": 600, "fin": 780}, PICO_INI, PICO_FIN) is False


def test_colocar_lo_mas_importante_va_al_pico():
    ventanas = [
        {"ini": 420, "fin": 540, "dur": 120},   # 7-9, PICO
        {"ini": 600, "fin": 780, "dur": 180},   # 10-13, ligera
    ]
    items = [
        {"titulo": "OneXotic: sprint", "tipo": "trabajo", "dur": 90, "prioridad": 1, "orden": 0},
        {"titulo": "Práctica: Guitarra", "tipo": "skill", "dur": 30, "prioridad": 8, "orden": 1},
    ]
    r = h.colocar(items, ventanas, buffer_min=10, pico_ini=PICO_INI, pico_fin=PICO_FIN)
    trabajo = next(b for b in r["bloques"] if b["tipo"] == "trabajo")
    skill = next(b for b in r["bloques"] if b["tipo"] == "skill")
    assert trabajo["ini_min"] == 420            # el más importante, en el pico
    assert skill["ini_min"] >= 600              # la skill, en la ventana ligera (no-pico)
    assert r["fuera"] == []


def test_colocar_recorta_por_capacidad_y_reporta_fuera():
    ventanas = [{"ini": 420, "fin": 540, "dur": 120}]  # solo cabe un bloque de 90
    items = [
        {"titulo": "A (importante)", "tipo": "trabajo", "dur": 90, "prioridad": 1, "orden": 0},
        {"titulo": "B (menos)", "tipo": "trabajo", "dur": 90, "prioridad": 2, "orden": 1},
    ]
    r = h.colocar(items, ventanas, buffer_min=10, pico_ini=PICO_INI, pico_fin=PICO_FIN)
    assert len(r["bloques"]) == 1 and r["bloques"][0]["titulo"] == "A (importante)"
    assert len(r["fuera"]) == 1 and r["fuera"][0]["titulo"] == "B (menos)"
    assert "no entró" in r["fuera"][0]["motivo"]


def test_colocar_mete_buffer_entre_bloques():
    ventanas = [{"ini": 420, "fin": 700, "dur": 280}]
    items = [
        {"titulo": "A", "tipo": "trabajo", "dur": 90, "prioridad": 1, "orden": 0},
        {"titulo": "B", "tipo": "trabajo", "dur": 90, "prioridad": 2, "orden": 1},
    ]
    r = h.colocar(items, ventanas, buffer_min=10, pico_ini=PICO_INI, pico_fin=PICO_FIN)
    a, b = r["bloques"][0], r["bloques"][1]
    assert b["ini_min"] - a["fin_min"] == 10   # buffer exacto entre bloques
