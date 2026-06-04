"""Lógica pura de la creación profunda: enganche de materiales, guard de
capacidad y disparo del árbol. Sin BD."""
from __future__ import annotations

from app.matix import creacion_proyecto as cp

SKILLS = ["calistenia", "guitarra", "ingles", "portugues", "trading"]


def test_detecta_material_por_nombre_y_alias():
    assert cp.detectar_material("Inglés B2", SKILLS) == "ingles"
    assert cp.detectar_material("aprender guitarra", SKILLS) == "guitarra"
    assert cp.detectar_material("English for work", SKILLS) == "ingles"  # alias
    assert cp.detectar_material("rutina de calistenia en barras", SKILLS) == "calistenia"
    assert cp.detectar_material("meter plata en trading de cripto", SKILLS) == "trading"


def test_no_detecta_cuando_no_hay_relacion():
    assert cp.detectar_material("Tienda de ropa OnExotic", SKILLS) is None
    assert cp.detectar_material("", SKILLS) is None


def test_guard_capacidad_con_espacio_recomienda():
    ev = cp.evaluar_capacidad(1, pendientes_abiertos=2)
    assert ev["permite_duro"] is True and ev["recomienda"] is True
    assert ev["espacio"] == 2


def test_guard_capacidad_cupo_lleno_no_recomienda():
    ev = cp.evaluar_capacidad(3, pendientes_abiertos=0)
    assert ev["permite_duro"] is False and ev["recomienda"] is False
    assert "tope" in ev["motivo"].lower() or "activos" in ev["motivo"].lower()
    assert ev["espacio"] == 0


def test_guard_capacidad_carga_alta_cuestiona_aunque_haya_cupo():
    ev = cp.evaluar_capacidad(2, pendientes_abiertos=10)
    # Hay cupo duro (2<3) pero la carga alta hace que NO lo recomiende.
    assert ev["permite_duro"] is True
    assert ev["recomienda"] is False
    assert "carga" in ev["motivo"].lower() or "sobrecompromiso" in ev["motivo"].lower()


def test_split_skills_vs_proyectos_de_trabajo():
    proyectos = [
        {"id": "p1", "nombre": "OneXotic", "es_skill": False},
        {"id": "s1", "nombre": "Inglés", "es_skill": True},
        {"id": "p2", "nombre": "Matix"},  # sin flag = trabajo
        {"id": "s2", "nombre": "Guitarra", "es_skill": True},
    ]
    assert [p["id"] for p in cp.solo_proyectos(proyectos)] == ["p1", "p2"]
    assert [p["id"] for p in cp.solo_skills(proyectos)] == ["s1", "s2"]
    assert cp.es_skill({"es_skill": True}) is True
    assert cp.es_skill({}) is False


def test_tope_blando_skills_avisa_pero_no_bloquea():
    # Con espacio (1 < 2): no excede, no bloquea.
    libre = cp.evaluar_capacidad_skill(1)
    assert libre["excede"] is False and libre["bloquea"] is False
    # Al tope (2 >= 2): AVISA pero NUNCA bloquea (un hobby no se gestiona con
    # candado).
    lleno = cp.evaluar_capacidad_skill(2)
    assert lleno["excede"] is True
    assert lleno["bloquea"] is False
    assert "aviso" in lleno["motivo"].lower() or "no te lo bloqueo" in lleno["motivo"].lower()
    assert cp.TOPE_SKILLS_ACTIVAS == 2 and cp.TOPE_PROYECTOS_ACTIVOS == 3


def test_intake_suficiente_para_disparar_arbol():
    # Falta estructura → todavía no.
    assert cp.intake_suficiente({"objetivo": "graduarme"}) is False
    # Objetivo + próximos pasos → suficiente.
    assert cp.intake_suficiente({"objetivo": "x", "proximos_pasos": [{"contenido": "p"}]}) is True
    # Objetivo + componentes → suficiente.
    assert cp.intake_suficiente({"objetivo": "x", "componentes": [{"contenido": "c"}]}) is True
    # Sin objetivo → no.
    assert cp.intake_suficiente({"componentes": [{"contenido": "c"}]}) is False
