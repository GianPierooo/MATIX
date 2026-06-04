"""Lógica pura del % de avance: ponderación por fase, manejo de la elaboración
progresiva, pesos por tamaño. Es la parte delicada — testeada a fondo. Sin BD."""
from __future__ import annotations

from app.matix import avance


def _n(id, parent, estado="pendiente", orden=0, gran="fino", tamano=None):
    d = {"id": id, "parent_id": parent, "estado": estado, "orden": orden, "granularidad": gran, "titulo": id}
    if tamano:
        d["tamano"] = tamano
    return d


def test_sin_plan_es_none():
    assert avance.porcentaje([]) is None
    # nodos sin raíces (todos con parent inexistente) → sin fases → None
    assert avance.porcentaje([_n("a", "x")]) is None


def test_todo_hecho_100_nada_0():
    nodos = [_n("f", None), _n("a", "f", "hecho"), _n("b", "f", "hecho")]
    assert avance.porcentaje(nodos) == 100
    nodos2 = [_n("f", None), _n("a", "f", "pendiente"), _n("b", "f", "pendiente")]
    assert avance.porcentaje(nodos2) == 0


def test_en_curso_vale_medio():
    nodos = [_n("f", None), _n("a", "f", "en_curso")]
    assert avance.porcentaje(nodos) == 50


def test_ponderacion_por_fase_no_por_hoja_cruda():
    # Fase 1 COMPLETA (gruesa, 1 nodo). Fase 2 ACTUAL fina con 10 hojas, 0
    # hechas. Fase 3 gruesa pendiente.
    nodos = [
        _n("f1", None, "hecho", 0, gran="grueso"),
        _n("f2", None, "pendiente", 1, gran="fino"),
        *[_n(f"l{i}", "f2", "pendiente", i) for i in range(10)],
        _n("f3", None, "pendiente", 2, gran="grueso"),
    ]
    # Por fase: (1 + 0 + 0)/3 = 33. (Contar hojas crudo daría ~1/12 ≈ 8 y
    # hundiría injustamente la fase 1 ya terminada.)
    assert avance.porcentaje(nodos) == 33


def test_fase_actual_detallada_aporta_su_fraccion_real():
    # 3 fases parejas; la actual (fina) va a la mitad, las otras pendientes.
    nodos = [
        _n("f1", None, "pendiente", 0, gran="fino"),
        _n("a", "f1", "hecho", 0), _n("b", "f1", "pendiente", 1),
        _n("f2", None, "pendiente", 1, gran="grueso"),
        _n("f3", None, "pendiente", 2, gran="grueso"),
    ]
    # (0.5 + 0 + 0)/3 = 16.67 → 17
    assert avance.porcentaje(nodos) == 17


def test_peso_por_tamano_dentro_de_la_fase():
    # En una fase: una hoja 'grande' (peso 3) hecha y una 'chico' (peso 1)
    # pendiente → 3/4 = 75% de la fase (única fase → 75% total).
    nodos = [
        _n("f", None),
        _n("g", "f", "hecho", 0, tamano="grande"),
        _n("c", "f", "pendiente", 1, tamano="chico"),
    ]
    assert avance.porcentaje(nodos) == 75


def test_peso_parejo_si_no_hay_tamano():
    nodos = [_n("f", None), _n("a", "f", "hecho"), _n("b", "f", "pendiente")]
    assert avance.porcentaje(nodos) == 50  # 1 de 2, peso parejo


def test_fase_interna_ignora_su_propio_estado():
    # La fase está 'pendiente' pero todos sus hijos hechos → 100% (su estado no
    # cuenta cuando tiene hijos; manda el contenido).
    nodos = [_n("f", None, "pendiente"), _n("a", "f", "hecho"), _n("b", "f", "hecho")]
    assert avance.porcentaje(nodos) == 100


def test_desglose_por_fase():
    nodos = [
        _n("f1", None, "pendiente", 0, gran="fino"),
        _n("a", "f1", "hecho", 0), _n("b", "f1", "pendiente", 1),
        _n("f2", None, "pendiente", 1, gran="grueso"),
    ]
    d = avance.desglose_por_fase(nodos)
    assert d[0]["fase"] == "f1" and d[0]["porcentaje"] == 50
    assert d[1]["fase"] == "f2" and d[1]["porcentaje"] == 0
