"""Lógica pura del árbol de descomposición: armado desde el perfil, elaboración
progresiva, render, progreso y sync con tareas completadas. Sin BD."""
from __future__ import annotations

from app.matix import arbol_proyecto as ar


def _det(contenido):
    return {"contenido": contenido}


def test_propuesta_desde_componentes_detalla_solo_la_fase_actual():
    perfil = {
        "nombre": "Tesis",
        "objetivo": "graduarme",
        "fase_actual": "Marco teórico",
        "componentes": [_det("Introducción"), _det("Marco teórico"), _det("Resultados")],
        "proximos_pasos": [_det("Leer 3 papers"), _det("Redactar 2 páginas")],
    }
    arbol = ar.armar_propuesta_arbol(perfil)
    assert [n["titulo"] for n in arbol] == ["Introducción", "Marco teórico", "Resultados"]
    # Solo la fase actual (Marco teórico) se detalla fino con los próximos pasos.
    actual = next(n for n in arbol if n["titulo"] == "Marco teórico")
    assert actual["granularidad"] == "fino"
    assert [h["titulo"] for h in actual["hijos"]] == ["Leer 3 papers", "Redactar 2 páginas"]
    # Las demás quedan gruesas y SIN hijos (anti-abrumo).
    for otra in arbol:
        if otra["titulo"] != "Marco teórico":
            assert otra["granularidad"] == "grueso" and otra["hijos"] == []


def test_propuesta_sin_fase_que_calce_usa_la_primera_como_actual():
    perfil = {
        "nombre": "App", "fase_actual": "no calza con nada",
        "componentes": [_det("Diseño"), _det("Backend")],
        "proximos_pasos": [_det("Wireframes")],
    }
    arbol = ar.armar_propuesta_arbol(perfil)
    assert arbol[0]["granularidad"] == "fino"  # primera = actual por defecto
    assert arbol[1]["granularidad"] == "grueso"


def test_propuesta_sin_componentes_una_raiz_con_pasos():
    perfil = {
        "nombre": "Mudanza", "objetivo": "mudarme a un depa nuevo",
        "componentes": [], "proximos_pasos": [_det("Buscar depa"), _det("Cotizar flete")],
    }
    arbol = ar.armar_propuesta_arbol(perfil)
    assert len(arbol) == 1
    assert arbol[0]["titulo"] == "mudarme a un depa nuevo"
    assert [h["titulo"] for h in arbol[0]["hijos"]] == ["Buscar depa", "Cotizar flete"]


def test_armar_arbol_texto_anida_y_marca_estado_y_grueso():
    nodos = [
        {"id": "r1", "parent_id": None, "titulo": "Marco teórico", "orden": 0, "estado": "en_curso", "granularidad": "fino"},
        {"id": "h1", "parent_id": "r1", "titulo": "Leer papers", "orden": 0, "estado": "hecho", "granularidad": "fino"},
        {"id": "r2", "parent_id": None, "titulo": "Resultados", "orden": 1, "estado": "pendiente", "granularidad": "grueso"},
    ]
    texto = ar.armar_arbol_texto(nodos)
    assert "[en curso] Marco teórico" in texto
    assert "  - [hecho] Leer papers" in texto  # hijo indentado
    assert "Resultados" in texto and "por desglosar" in texto
    assert "id=r1" in texto


def test_progreso_cuenta_estados():
    nodos = [
        {"estado": "hecho"}, {"estado": "hecho"}, {"estado": "en_curso"}, {"estado": "pendiente"},
    ]
    p = ar.progreso_arbol(nodos)
    assert p == {"total": 4, "hechos": 2, "en_curso": 1, "pendientes": 1}


def test_sync_nodos_de_tarea_completada():
    nodos = [
        {"id": "n1", "tarea_id": "t-AAA"},
        {"id": "n2", "tarea_id": None},
        {"id": "n3", "tarea_id": "t-AAA"},
        {"id": "n4", "tarea_id": "t-BBB"},
    ]
    assert set(ar.nodos_de_tarea(nodos, "t-AAA")) == {"n1", "n3"}
    assert ar.nodos_de_tarea(nodos, "t-ZZZ") == []


def test_arbol_texto_vacio():
    assert "Todavía no hay plan" in ar.armar_arbol_texto([])
