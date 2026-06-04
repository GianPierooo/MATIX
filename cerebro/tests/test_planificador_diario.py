"""Lógica pura del planificador diario: selección del set, escalación,
anti-fatiga y textos de cierre. Sin BD."""
from __future__ import annotations

from datetime import timedelta

from app.matix import planificador_diario as pl


def _nodo(id, parent, titulo, orden=0, estado="pendiente", gran="fino"):
    return {"id": id, "parent_id": parent, "titulo": titulo, "orden": orden,
            "estado": estado, "granularidad": gran}


def test_candidatos_toma_la_primera_hoja_fina_pendiente_de_cada_fase():
    nodos = [
        _nodo("f1", None, "Fase 1", 0, gran="fino"),
        _nodo("a", "f1", "Paso A", 0, estado="hecho"),
        _nodo("b", "f1", "Paso B", 1),  # primera pendiente de Fase 1
        _nodo("c", "f1", "Paso C", 2),  # bloqueada (va después de B)
        _nodo("f2", None, "Fase 2 (lejana)", 1, gran="grueso"),  # sin hijos → no aporta
    ]
    cands = pl.candidatos_proyecto(nodos)
    assert [c["id"] for c in cands] == ["b"]  # solo B (C queda bloqueada; f2 es gruesa)


def test_candidatos_ignora_fase_gruesa_sin_desglosar():
    nodos = [_nodo("f1", None, "Fase lejana", 0, gran="grueso")]
    assert pl.candidatos_proyecto(nodos) == []


def test_seleccionar_set_reparte_entre_proyectos_y_respeta_tamano():
    proyectos = [
        {"id": "p1", "nombre": "Tesis", "prioridad": 1},
        {"id": "p2", "nombre": "App", "prioridad": 2},
    ]
    nodos = {
        "p1": [_nodo("f", None, "F"), _nodo("p1a", "f", "T1", 0), _nodo("p1b", "f", "T2", 1)],
        "p2": [_nodo("g", None, "G"), _nodo("p2a", "g", "A1", 0)],
    }
    # candidatos: p1 → [T1] (primera de su fase), p2 → [A1]. tamano 3 → ambas.
    s = pl.seleccionar_set(proyectos, nodos, tamano=3)
    titulos = [x["titulo"] for x in s]
    assert "T1" in titulos and "A1" in titulos
    assert len(s) <= 3


def test_seleccionar_set_prioriza_y_limita():
    proyectos = [{"id": "p1", "nombre": "P1", "prioridad": 1}, {"id": "p2", "nombre": "P2", "prioridad": 2}]
    nodos = {
        "p1": [_nodo("f", None, "F"), _nodo("x", "f", "X", 0)],
        "p2": [_nodo("g", None, "G"), _nodo("y", "g", "Y", 0)],
    }
    s = pl.seleccionar_set(proyectos, nodos, tamano=1)
    assert len(s) == 1 and s[0]["titulo"] == "X"  # prioridad 1 primero


def test_anti_fatiga_escala_el_intervalo():
    assert pl.factor_anti_fatiga(0) == 1
    assert pl.factor_anti_fatiga(2) == 2
    assert pl.factor_anti_fatiga(5) == 4
    base = pl.intervalo_escalacion("alta", 0)
    fatigado = pl.intervalo_escalacion("alta", 5)
    assert fatigado == base * 4  # mismo tipo, más espaciado, sin apagar


def test_intervalo_por_intensidad():
    assert pl.intervalo_escalacion("alta", 0) == timedelta(minutes=45)
    assert pl.intervalo_escalacion("media", 0) == timedelta(minutes=90)
    assert pl.intervalo_escalacion("baja", 0) == timedelta(minutes=180)
    assert pl.tope_escalaciones_dia("alta") > pl.tope_escalaciones_dia("baja")


def test_resumen_cierre_celebra_y_no_culpa():
    # Todo hecho → celebra.
    t, c = pl.resumen_cierre(3, 3)
    assert "cerrad" in (t + c).lower() or "cerró" in c.lower() or "cerraste" in c.lower()
    # Parcial → suma + rueda sin culpa (no "fracaso").
    _, c2 = pl.resumen_cierre(1, 3)
    assert "mañana" in c2.lower() and "culpa" in c2.lower()
    assert "fracaso" not in c2.lower()
    # Nada → sin drama.
    _, c3 = pl.resumen_cierre(0, 3)
    assert "drama" in c3.lower() and "fracaso" not in c3.lower()


def test_texto_escalacion_rota_y_es_sano():
    a = pl.texto_escalacion(2, 0)
    b = pl.texto_escalacion(2, 1)
    assert a[1] != b[1]  # rota
    assert "2" in a[1]  # nombra cuántas faltan


def test_dosis_skill_es_suave_opcional_y_rota():
    a = pl.texto_dosis_skill("Guitarra", 0)
    b = pl.texto_dosis_skill("Guitarra", 1)
    assert a[1] != b[1]  # rota
    assert "Guitarra" in a[1]  # nombra la skill
    # Suave/opcional: nada de lenguaje de obligación.
    txt = (a[0] + a[1]).lower()
    assert "sin presión" in txt or "si te provoca" in txt or "por gusto" in txt
    assert "tienes que" not in txt and "obligat" not in txt


def test_celebra_skill_es_positivo():
    _, c = pl.texto_celebra_skill("Inglés")
    assert "Inglés" in c
    assert "suma" in c.lower() or "cuenta" in c.lower()


def test_tasa_cierre():
    assert pl.tasa_cierre(0, 0) is None  # sin datos no castiga
    assert pl.tasa_cierre(2, 4) == 0.5
    assert pl.tasa_cierre(3, 3) == 1.0


def test_ajustar_tamano_set_reduce_cuando_va_atrasado_y_nunca_apila():
    # Sin datos o ritmo bueno → mantiene la base (nunca sube por encima).
    assert pl.ajustar_tamano_set(3, None, 0)["tamano"] == 3
    assert pl.ajustar_tamano_set(3, 1.0, 0)["tamano"] == 3
    # Cierra poco (tasa baja) → recorta fuerte (anti-patrón: no apilar).
    assert pl.ajustar_tamano_set(3, 0.3, 0)["tamano"] == 1
    # Ritmo algo flojo → recorta un poco.
    assert pl.ajustar_tamano_set(3, 0.6, 0)["tamano"] == 2
    # Carga arrastrada alta (>= base) → recorta aunque la tasa sea buena.
    assert pl.ajustar_tamano_set(3, 1.0, 3)["tamano"] == 1
    # Nunca baja de 1.
    assert pl.ajustar_tamano_set(2, 0.1, 0)["tamano"] == 1


def test_elegir_skill_del_dia_rota_por_dia():
    skills = [
        {"id": "a", "nombre": "Inglés", "creado_en": "2026-01-01"},
        {"id": "b", "nombre": "Guitarra", "creado_en": "2026-02-01"},
    ]
    d0 = pl.elegir_skill_del_dia(skills, 0)
    d1 = pl.elegir_skill_del_dia(skills, 1)
    d2 = pl.elegir_skill_del_dia(skills, 2)
    assert d0["id"] == "a" and d1["id"] == "b" and d2["id"] == "a"  # round-robin
    assert pl.elegir_skill_del_dia([], 5) is None  # sin skills, nada
