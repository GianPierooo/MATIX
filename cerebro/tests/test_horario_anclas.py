"""Prioridad y naturaleza de los bloques del plan (lógica PURA, sin BD):

- Una PRÁCTICA de skill nunca es FIJA: si una ancla coincide con una skill, NO
  entra como compromiso fijo (se coloca tentativa). Solo clases y eventos son
  fijos; las anclas que NO son skill (rutinas que el usuario fijó) siguen fijas.
- El TRABAJO de proyecto gana el bloque pico; las prácticas van a tiempo ligero.
- Todo lo que coloca `colocar` es tentativo (movible)."""
from __future__ import annotations

from app.matix import horario as h

PICO_INI = 6 * 60
PICO_FIN = 9 * 60


# ── anclas_fijas: una práctica nunca es fija ─────────────────────────────────

def test_ancla_que_es_skill_NO_entra_como_fija():
    anclas = [
        {"titulo": "Calistenia", "inicio": "07:00", "fin": "07:45",
         "dias": [1, 2, 3, 4, 5, 6, 7]},
    ]
    # Calistenia es una skill activa → no debe quedar como ancla fija.
    out = h.anclas_fijas(anclas, iso_weekday=1, skills_norm={"calistenia"})
    assert out == []


def test_ancla_que_NO_es_skill_sigue_fija():
    anclas = [
        {"titulo": "Almuerzo", "inicio": "13:00", "fin": "14:00",
         "dias": [1, 2, 3, 4, 5, 6, 7]},
    ]
    out = h.anclas_fijas(anclas, iso_weekday=1, skills_norm={"calistenia"})
    assert len(out) == 1
    assert out[0]["tipo"] == "ancla"
    assert out[0]["titulo"] == "Almuerzo"
    assert out[0]["ini_min"] == 13 * 60


def test_ancla_match_skill_ignora_tildes_y_mayusculas():
    anclas = [{"titulo": "  CALISTENIA ", "inicio": "07:00", "fin": "07:45"}]
    assert h.anclas_fijas(anclas, iso_weekday=3, skills_norm={"calistenia"}) == []


def test_ancla_respeta_el_dia_de_la_semana():
    anclas = [{"titulo": "Gimnasio", "inicio": "06:00", "fin": "07:00",
               "dias": [1, 3, 5]}]  # lun/mié/vie
    assert h.anclas_fijas(anclas, iso_weekday=2, skills_norm=set()) == []  # martes
    assert len(h.anclas_fijas(anclas, iso_weekday=1, skills_norm=set())) == 1


def test_ancla_con_horas_invalidas_se_descarta():
    anclas = [{"titulo": "Rara", "inicio": "08:00", "fin": "07:00"}]  # fin<=ini
    assert h.anclas_fijas(anclas, iso_weekday=1, skills_norm=set()) == []


# ── La práctica colocada es tentativa; el trabajo gana el pico ───────────────

def test_skill_colocada_es_tentativa_nunca_fija():
    ventanas = [{"ini": 600, "fin": 720, "dur": 120}]
    items = [{"titulo": "Práctica: Guitarra", "tipo": "skill", "dur": 30,
              "prioridad": 8, "orden": 0, "skill": "Guitarra"}]
    r = h.colocar(items, ventanas, buffer_min=10, pico_ini=PICO_INI, pico_fin=PICO_FIN)
    assert len(r["bloques"]) == 1
    assert r["bloques"][0]["tipo"] == "skill"
    assert r["bloques"][0]["tentativo"] is True  # movible, NUNCA fijo


def test_trabajo_gana_el_pico_sobre_la_practica():
    # Pico libre (la skill-ancla ya no lo bloquea) → el trabajo lo toma.
    ventanas = [
        {"ini": 6 * 60, "fin": 9 * 60, "dur": 180},    # PICO 6-9
        {"ini": 11 * 60, "fin": 13 * 60, "dur": 120},  # ligera
    ]
    items = [
        {"titulo": "OneXotic: deep work", "tipo": "trabajo", "dur": 90,
         "prioridad": 1, "orden": 0},
        {"titulo": "Práctica: Inglés", "tipo": "skill", "dur": 30,
         "prioridad": 8, "orden": 1},
    ]
    r = h.colocar(items, ventanas, buffer_min=10, pico_ini=PICO_INI, pico_fin=PICO_FIN)
    trabajo = next(b for b in r["bloques"] if b["tipo"] == "trabajo")
    skill = next(b for b in r["bloques"] if b["tipo"] == "skill")
    assert trabajo["ini_min"] == 6 * 60        # trabajo en el pico
    assert not h.es_pico(
        {"ini": skill["ini_min"], "fin": skill["fin_min"]}, PICO_INI, PICO_FIN
    )  # la práctica, fuera del pico
