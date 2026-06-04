"""Lógica pura del intake analítico: esquema por tipo, detección de tipo y de
huecos, gate de completitud y plan en capas. Sin BD."""
from __future__ import annotations

from app.matix import intake_analitico as ia


def test_detecta_tipo_por_palabras_clave():
    assert ia.detectar_tipo("Quiero vender ropa con mi marca OnExotic") == "negocio"
    assert ia.detectar_tipo("Llegar a inglés B2") == "skill"
    assert ia.detectar_tipo("Bajar de peso y ganar masa muscular") == "fisico"
    assert ia.detectar_tipo("Construir una app de notas") == "construir"
    assert ia.detectar_tipo("Algo sin categoría clara") == "generico"


def test_esquema_por_tipo_tiene_requeridos_propios():
    neg = ia.esquema_de("negocio")
    claves = {p["clave"] for p in neg["requeridos"]}
    # Específicos de negocio + comunes (meta/criterio/porqué).
    assert {"que_vende", "precios_margenes", "cuello_botella"} <= claves
    assert {"meta_plazo", "criterio_exito", "porque"} <= claves
    sk = {p["clave"] for p in ia.esquema_de("skill")["requeridos"]}
    assert {"nivel_actual", "materiales"} <= sk


def test_siguiente_pregunta_prioriza_requeridos_y_no_repite():
    # Nada capturado → primera requerida (que_vende para negocio).
    q = ia.siguiente_pregunta_intake("negocio", {}, [])
    assert q["clave"] == "que_vende" and q["requerido"] is True
    # Con que_vende ya preguntado, pasa a la siguiente requerida.
    q2 = ia.siguiente_pregunta_intake("negocio", {}, ["que_vende"])
    assert q2["clave"] != "que_vende" and q2["requerido"] is True


def test_huecos_separa_requeridos_y_opcionales():
    cap = {p["clave"]: "x" for p in ia.esquema_de("generico")["requeridos"]}
    h = ia.huecos("generico", cap)
    assert h["requeridos_faltantes"] == []  # todos los requeridos puestos
    assert "recursos" in h["opcionales_pendientes"]  # opcionales siguen pendientes


def test_gate_bloquea_hasta_tener_requeridos():
    # Falta casi todo → no listo.
    g0 = ia.puede_planear("negocio", {"que_vende": "ropa"})
    assert g0["listo"] is False and "meta_plazo" in g0["faltan"]
    # Todos los requeridos puestos → listo.
    cap = {p["clave"]: "x" for p in ia.esquema_de("negocio")["requeridos"]}
    g1 = ia.puede_planear("negocio", cap)
    assert g1["listo"] is True and g1["faltan"] == []


def test_horizonte_por_indice():
    assert ia.horizonte_por_indice(0, 4) == "corto"
    assert ia.horizonte_por_indice(3, 4) == "largo"
    assert ia.horizonte_por_indice(1, 4) == "medio"
    assert ia.horizonte_por_indice(0, 1) == "corto"


def test_plan_en_capas_estructura_visión_hitos_tareas():
    plan = ia.armar_plan_capas(
        vision="Marca rentable en 2 años",
        hitos=[
            {"titulo": "Primeras ventas", "criterio": "10 ventas/mes"},
            {"titulo": "Punto de equilibrio", "criterio": "ingresos=gastos"},
            {"titulo": "Escala", "criterio": "100 ventas/mes"},
        ],
        tareas_corto=["Sacar fotos del drop", "Definir precios"],
    )
    assert plan["vision"].startswith("Marca")
    assert plan["hitos"][0]["horizonte"] == "corto"
    assert plan["hitos"][-1]["horizonte"] == "largo"
    assert all(t["horizonte"] == "corto" for t in plan["tareas_corto"])
    assert plan["hitos"][0]["criterio"] == "10 ventas/mes"
