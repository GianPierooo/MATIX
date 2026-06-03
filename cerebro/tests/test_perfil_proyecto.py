"""Lógica pura del perfil de proyectos: armado del perfil, máquina de la
entrevista y estado de avance. Sin BD."""
from __future__ import annotations

from app.matix import perfil_proyecto as pp


def _detalle(tipo, contenido, estado="abierto", id="d1", creado_en="2026-06-03T12:00:00Z"):
    return {"id": id, "tipo": tipo, "contenido": contenido, "estado": estado, "creado_en": creado_en}


def test_armar_perfil_agrupa_por_tipo_y_excluye_archivados():
    proyecto = {"id": "p1", "nombre": "Tesis", "objetivo": "graduarme", "estado_actual": "marco teórico"}
    detalles = [
        _detalle("componente", "Capítulo 1", id="c1"),
        _detalle("proximo_paso", "Leer 3 papers", id="n1"),
        _detalle("blocker", "Falta acceso a la biblioteca", id="b1"),
        _detalle("nota", "El asesor sugirió otro enfoque", id="no1"),
        _detalle("componente", "viejo", estado="archivado", id="c2"),
    ]
    perfil = pp.armar_perfil(proyecto, detalles)
    assert perfil["objetivo"] == "graduarme"
    assert [c["contenido"] for c in perfil["componentes"]] == ["Capítulo 1"]  # archivado fuera
    assert len(perfil["proximos_pasos"]) == 1 and len(perfil["blockers"]) == 1
    assert len(perfil["notas"]) == 1


def test_siguiente_pregunta_ordena_y_salta_lo_respondido():
    # objetivo ya respondido → la primera pendiente es estado_actual.
    perfil = {"nombre": "Tesis", "objetivo": "graduarme", "componentes": [], "proximos_pasos": [], "blockers": []}
    q = pp.siguiente_pregunta(perfil, preguntados=[])
    assert q["campo"] == "estado_actual"


def test_siguiente_pregunta_detalle_pendiente_si_lista_vacia():
    perfil = {
        "nombre": "Tesis", "objetivo": "x", "estado_actual": "y", "fase_actual": "z",
        "componentes": [], "proximos_pasos": [], "blockers": [],
    }
    q = pp.siguiente_pregunta(perfil, preguntados=[])
    assert q["campo"] == "componente" and q["clase"] == "detalle"


def test_siguiente_pregunta_no_repite_lo_preguntado():
    # blocker ya preguntado (aunque la lista esté vacía: el usuario dijo «nada»)
    perfil = {
        "nombre": "Tesis", "objetivo": "x", "estado_actual": "y", "fase_actual": "z",
        "componentes": [_detalle("componente", "c")], "proximos_pasos": [_detalle("proximo_paso", "p")],
        "blockers": [],
    }
    q = pp.siguiente_pregunta(perfil, preguntados=["blocker"])
    # salta blocker (ya preguntado) → pregunta horizonte
    assert q["campo"] == "horizonte"


def test_entrevista_completa_cuando_no_falta_nada():
    perfil = {
        "nombre": "Tesis", "objetivo": "x", "estado_actual": "y", "fase_actual": "z", "horizonte": "1 año",
        "componentes": [_detalle("componente", "c")], "proximos_pasos": [_detalle("proximo_paso", "p")],
        "blockers": [],
    }
    # blocker preguntado (vacío a propósito) → ya no falta nada.
    assert pp.siguiente_pregunta(perfil, preguntados=["blocker"]) is None
    est = pp.estado_entrevista(perfil, preguntados=["blocker"])
    assert est["completa"] is True and est["faltan"] == []


def test_estado_entrevista_cuenta_avance():
    perfil = {"nombre": "T", "objetivo": "x", "componentes": [], "proximos_pasos": [], "blockers": []}
    est = pp.estado_entrevista(perfil, preguntados=[])
    assert est["total"] == len(pp.PREGUNTAS_ENTREVISTA)
    assert est["resueltas"] == 1  # solo objetivo
    assert "componente" in est["faltan"]


def test_armar_perfil_texto_incluye_ids_para_corregir():
    perfil = pp.armar_perfil(
        {"id": "p1", "nombre": "Tesis", "objetivo": "graduarme"},
        [_detalle("proximo_paso", "Leer papers", id="n1")],
    )
    texto = pp.armar_perfil_texto(perfil)
    assert "Tesis" in texto and "graduarme" in texto
    assert "Leer papers" in texto and "id=n1" in texto


def test_armar_perfil_texto_vacio():
    perfil = pp.armar_perfil({"id": "p1", "nombre": "Nuevo"}, [])
    assert "Todavía no tengo nada anotado" in pp.armar_perfil_texto(perfil)
