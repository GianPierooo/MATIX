"""Filtrado de tools por turno (palanca de tokens, sin perder potencia)."""
from __future__ import annotations

from app.matix import seleccion_tools as st
from app.matix.tools import TOOL_DEFINITIONS


def _nombres(defs):
    return {t["function"]["name"] for t in defs}


def test_core_siempre_presente_en_comando_simple():
    out = st.filtrar_tools(TOOL_DEFINITIONS, "crea una tarea: comprar pan")
    nombres = _nombres(out)
    # Todo el CORE que existe en el catálogo debe estar.
    catalogo = _nombres(TOOL_DEFINITIONS)
    for c in st.CORE:
        if c in catalogo:
            assert c in nombres, c


def test_comando_simple_recorta_especializadas():
    out = st.filtrar_tools(TOOL_DEFINITIONS, "márcala como hecha")
    nombres = _nombres(out)
    # No arrastra finanzas / pc / teléfono en un comando que no los menciona.
    assert "crear_movimiento" not in nombres
    assert "pc_mover_archivo" not in nombres
    assert "escribir_whatsapp" not in nombres
    assert len(out) < len(TOOL_DEFINITIONS)  # de verdad recortó


def test_finanzas_se_dispara_por_keyword():
    out = _nombres(st.filtrar_tools(TOOL_DEFINITIONS, "gasté 20 soles en el super"))
    assert "registrar_movimientos" in out or "crear_movimiento" in out


def test_pc_se_dispara_por_keyword():
    out = _nombres(st.filtrar_tools(TOOL_DEFINITIONS, "resume el pdf de mi compu"))
    assert "pc_resumir_documento" in out


def test_pc_apps_se_disparan_por_keyword():
    # 6.2: abrir apps / sesión de foco / editor deben traer las tools de apps.
    for msg in ["abre el editor en la pc", "arranca una sesión de foco",
                "abre chrome", "lanza el programa"]:
        out = _nombres(st.filtrar_tools(TOOL_DEFINITIONS, msg))
        assert "pc_abrir_app" in out, msg
        assert "pc_ejecutar_tarea" in out, msg


def test_telefono_se_dispara_por_keyword():
    out = _nombres(st.filtrar_tools(TOOL_DEFINITIONS, "mándale un whatsapp a Ana"))
    assert "escribir_whatsapp" in out


def test_proyecto_avanzado_se_dispara():
    out = _nombres(st.filtrar_tools(TOOL_DEFINITIONS, "trabajemos el árbol del proyecto tesis"))
    assert "generar_arbol_proyecto" in out or "ver_arbol_proyecto" in out


def test_mensaje_largo_manda_todas():
    # >600 chars: multi-tema/complejo → todas, para no recortar potencia.
    largo = "necesito que " + ("analices y reorganices todo " * 25)
    assert len(st._norm(largo)) > st._UMBRAL_LARGO
    out = st.filtrar_tools(TOOL_DEFINITIONS, largo)
    assert len(out) == len(TOOL_DEFINITIONS)  # no recorta potencia en lo complejo


def test_mensaje_mediano_no_manda_todas():
    # El caso que arregla #3: un turno conversacional de 2-3 frases (entre el
    # viejo umbral 240 y el nuevo 600) YA NO vuelca las 124 tools; se queda con
    # el CORE (+ los grupos que dispare). Sin keywords de grupo → solo CORE.
    mediano = (
        "quiero contarte que estuve pensando en como me fue esta semana y me di "
        "cuenta de que tengo varias cosas dando vueltas en la cabeza; no es nada "
        "urgente ni grave, pero me gustaria sentirme un poco mas ordenado y "
        "tranquilo para no llegar al fin de semana con la sensacion de que todo "
        "se me junto y termine corriendo a ultimo momento como siempre me pasa"
    )
    n = len(st._norm(mediano))
    assert 240 < n < st._UMBRAL_LARGO, n  # es "mediano": el viejo 240 lo volcaba
    out = st.filtrar_tools(TOOL_DEFINITIONS, mediano)
    assert len(out) < len(TOOL_DEFINITIONS)  # ya no manda el catálogo entero


def test_modo_pesado_manda_todas():
    out = st.filtrar_tools(TOOL_DEFINITIONS, "sigamos", modo="tesis")
    assert len(out) == len(TOOL_DEFINITIONS)


def test_nunca_recorta_bajo_la_mitad_del_core():
    # Aun con un mensaje vacío, devuelve al menos el CORE (no rompe potencia).
    out = st.filtrar_tools(TOOL_DEFINITIONS, "")
    assert len(out) >= len(st.CORE) // 2


def test_orden_preservado():
    out = st.filtrar_tools(TOOL_DEFINITIONS, "crea tarea X")
    nombres_out = [t["function"]["name"] for t in out]
    nombres_full = [t["function"]["name"] for t in TOOL_DEFINITIONS]
    # El subconjunto mantiene el orden relativo del catálogo.
    assert nombres_out == [n for n in nombres_full if n in set(nombres_out)]
