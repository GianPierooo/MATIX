"""Backlog VIVO en el plan del día: las tareas SIN fecha ya no mueren invisibles
— el planificador las ofrece como tarea ligera en huecos cuando hay espacio.

Lógica PURA (sin BD): `items_backlog(tareas, set_tarea_ids, dur_tarea_min)`."""
from __future__ import annotations

from app.matix import horario as h


def _t(**kwargs):
    base = {"id": "x", "titulo": "Tarea x", "completada": False,
            "vence_en": None, "bloque_inicio": None}
    base.update(kwargs)
    return base


def test_backlog_recoge_sin_fecha_ni_bloque():
    tareas = [_t(id="a", titulo="Pendiente sin fecha")]
    out = h.items_backlog(tareas, set_tarea_ids=set(), dur_tarea_min=20)
    assert len(out) == 1
    assert out[0]["tarea_id"] == "a"
    assert out[0]["tipo"] == "tarea"
    assert out[0]["backlog"] is True
    assert out[0]["dur"] == 20


def test_backlog_excluye_completadas_y_con_fecha_y_con_bloque():
    tareas = [
        _t(id="a", completada=True),
        _t(id="b", vence_en="2026-06-10T10:00:00Z"),
        _t(id="c", bloque_inicio="2026-06-05T09:00:00Z"),
        _t(id="d", titulo="Sí entra"),
    ]
    out = h.items_backlog(tareas, set_tarea_ids=set(), dur_tarea_min=20)
    assert [i["tarea_id"] for i in out] == ["d"]


def test_backlog_excluye_las_que_estan_en_el_set():
    tareas = [_t(id="a"), _t(id="b")]
    out = h.items_backlog(
        tareas, set_tarea_ids={"a"}, dur_tarea_min=20,
    )
    assert [i["tarea_id"] for i in out] == ["b"]


def test_backlog_respeta_tope_para_no_ahogar_el_dia():
    tareas = [_t(id=f"t{i}") for i in range(10)]
    out = h.items_backlog(tareas, set_tarea_ids=set(), dur_tarea_min=20, tope=3)
    assert len(out) == 3


def test_backlog_va_al_final_por_prioridad_y_orden_altos():
    # El planificador ordena por (prioridad, orden) — el backlog debe quedar
    # detrás del set (prio del proyecto) y de las skills (prio 8).
    out = h.items_backlog(
        [_t(id="a")], set_tarea_ids=set(), dur_tarea_min=20,
    )
    assert out[0]["prioridad"] >= 9
    assert out[0]["orden"] >= 200
