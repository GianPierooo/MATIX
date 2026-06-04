"""Lógica pura de importar un plan pegado: normalización, etiquetado de
horizonte → granularidad, detección de huecos y plan → nodos del árbol. Sin BD.
"""
from __future__ import annotations

from app.matix import importar_plan as ip


def _plan_negocio():
    return {
        "objetivo": "Vivir de mi marca de ropa",
        "tipo": "negocio",
        "parametros": {
            "porque": "quiero independencia", "meta_plazo": "100 ventas/mes en 1 año",
            "criterio_exito": "ingresos > gastos", "que_vende": "polos oversize",
            "propuesta_valor": "diseño propio", "cliente": "jóvenes urbanos",
            "etapa": "primeras ventas", "canales": "instagram + web",
            "precios_margenes": "S/80, 50% margen", "cuello_botella": "tráfico",
            "horizonte_anios": "2 años", "presupuesto": "S/3000", "tiempo_semanal": "15h",
        },
        "fases": [
            {"titulo": "Lanzamiento", "horizonte": "corto", "nodos": ["Sacar fotos", "Definir precios"]},
            {"titulo": "Tracción", "horizonte": "medio", "nodos": ["Pauta", "Colaboraciones"]},
            {"titulo": "Escala", "horizonte": "largo", "nodos": ["Producción mayor"]},
        ],
    }


def test_granularidad_de_horizonte():
    assert ip.granularidad_de_horizonte("corto") == "fino"
    assert ip.granularidad_de_horizonte("largo") == "grueso"
    assert ip.granularidad_de_horizonte("medio") == "grueso"


def test_normalizar_plan_limpia_y_etiqueta():
    plan = ip.normalizar_plan(_plan_negocio())
    assert plan["tipo"] == "negocio"
    assert [f["granularidad"] for f in plan["fases"]] == ["fino", "grueso", "grueso"]
    assert plan["fases"][0]["nodos"] == ["Sacar fotos", "Definir precios"]


def test_normalizar_infiere_tipo_si_falta():
    est = {"objetivo": "Llegar a inglés B2", "fases": [{"titulo": "Base", "nodos": []}]}
    plan = ip.normalizar_plan(est)
    assert plan["tipo"] == "skill"
    # primera fase sin horizonte → corto (fina) por defecto
    assert plan["fases"][0]["granularidad"] == "fino"


def test_huecos_plan_detecta_faltantes():
    incompleto = ip.normalizar_plan({
        "objetivo": "Vender ropa", "tipo": "negocio",
        "parametros": {"que_vende": "polos"},
        "fases": [{"titulo": "Inicio", "nodos": []}],
    })
    g = ip.huecos_plan(incompleto)
    assert g["listo"] is False and "meta_plazo" in g["faltan"]
    # Plan completo → listo.
    completo = ip.normalizar_plan(_plan_negocio())
    assert ip.huecos_plan(completo)["listo"] is True


def test_plan_a_nodos_respeta_elaboracion_progresiva():
    plan = ip.normalizar_plan(_plan_negocio())
    nodos = ip.plan_a_nodos(plan["fases"])
    corto = nodos[0]
    assert corto["granularidad"] == "fino"
    assert [h["titulo"] for h in corto["hijos"]] == ["Sacar fotos", "Definir precios"]
    # fases lejanas: gruesas, SIN hijos, su detalle va a notas (no se aplana)
    largo = nodos[2]
    assert largo["granularidad"] == "grueso" and largo["hijos"] == []
    assert "Producción mayor" in (largo["notas"] or "")


def test_resumen_importacion_muestra_perfil_y_arbol():
    txt = ip.resumen_importacion(ip.normalizar_plan(_plan_negocio()))
    assert "Objetivo" in txt and "Lanzamiento" in txt
    assert "por desglosar" in txt.lower() or "gruesa" in txt.lower()
