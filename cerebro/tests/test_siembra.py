"""Lógica pura de la siembra de tareas inmediatas: qué nodos del árbol surgen
como tareas reales de corto plazo. Sin BD."""
from __future__ import annotations

from app.matix import siembra_tareas as st


def _n(id, parent, gran="fino", estado="pendiente", orden=0, tarea_id=None):
    return {
        "id": id, "parent_id": parent, "granularidad": gran, "estado": estado,
        "orden": orden, "titulo": id, "tarea_id": tarea_id,
    }


def test_elige_finas_pendientes_sin_tarea_en_orden():
    nodos = [
        _n("f1", None, "fino", orden=0),                 # fase corto (tiene hijos)
        _n("a", "f1", "fino", orden=0, estado="hecho"),  # hecho → no
        _n("b", "f1", "fino", orden=1, tarea_id="t9"),   # ya tiene tarea → no
        _n("c", "f1", "fino", orden=2),                   # ✓
        _n("d", "f1", "fino", orden=3),                   # ✓
        _n("e", "f1", "fino", orden=4),                   # ✓ pero supera el máximo
        _n("f2", None, "grueso", orden=1),               # fase gruesa sin hijos → no aporta
    ]
    out = st.nodos_inmediatos(nodos, 2)
    assert [n["id"] for n in out] == ["c", "d"]


def test_respeta_dosificacion_maximo():
    nodos = [_n("f", None, "fino")] + [
        _n(f"h{i}", "f", "fino", orden=i) for i in range(10)
    ]
    assert len(st.nodos_inmediatos(nodos, 3)) == 3


def test_ignora_fases_gruesas_y_arbol_sin_finas():
    # Solo fases gruesas sin desglosar → nada que sembrar (un bloque a la vez).
    nodos = [_n("g", None, "grueso", estado="pendiente")]
    assert st.nodos_inmediatos(nodos, 3) == []
    assert st.nodos_inmediatos([], 3) == []


def test_recorre_varias_fases_finas():
    nodos = [
        _n("f1", None, "fino", orden=0),
        _n("a", "f1", "fino", orden=0, estado="hecho"),  # f1 ya hecha
        _n("f2", None, "fino", orden=1),
        _n("b", "f2", "fino", orden=0),                   # ✓ siguiente fase fina
    ]
    out = st.nodos_inmediatos(nodos, 3)
    assert [n["id"] for n in out] == ["b"]
