"""Capa 6 · regresiones del caso «abre Spotify» (500 + ruteo + autoconocimiento).

Tres bugs, tres redes:

1. PARIDAD emisor↔schema: las tools de PC emiten `accion_dispositivo` de tipo
   `pc_accion`; el Literal de `AccionDispositivo.tipo` no lo incluía → la
   respuesta del chat no validaba contra `ChatResponse` y el endpoint moría en
   un 500 mudo. Aquí el bloque REAL que emite `_pc_propuesta` se valida contra
   el schema REAL — si alguien agrega un tipo nuevo sin tocar el schema, esto
   revienta en CI, no en producción.

2. RUTEO 6.3: las descripciones deben mandar los pedidos multi-paso («abre X y
   haz Y dentro») a `pc_controlar_pantalla`, no a `pc_abrir_app` a secas.

3. AUTOCONOCIMIENTO fuente única: la sección PC del system prompt se GENERA del
   catálogo de tools; cada tool `pc_*` del catálogo debe aparecer en ella.
   El texto suelto viejo decía «controlar la PC: capa futura» y el modelo le
   creía. Todo PURO (sin red, sin BD).
"""
from __future__ import annotations

from typing import get_args

from app.matix import capacidades_pc, tools
from app.schemas.matix import AccionDispositivo, ChatResponse


# ── 1) Paridad emisor ↔ schema (el 500 del caso Spotify) ─────────────────────


def test_pc_propuesta_real_valida_contra_el_schema():
    """El bloque accion_dispositivo que emite _pc_propuesta (el REAL, no una
    copia) debe validar contra AccionDispositivo. Este era el 500."""
    r = tools._pc_propuesta(
        "abrir_app", {"nombre": "spotify"}, "Abrir «spotify» en tu PC."
    )
    bloque = r["datos"]["accion_dispositivo"]
    acc = AccionDispositivo(**bloque)  # no debe lanzar
    assert acc.tipo == "pc_accion"
    assert acc.requiere_confirmacion is True


def test_chat_response_acepta_pc_accion():
    """La respuesta completa del chat (la que serializa FastAPI) acepta una
    propuesta de PC. Reproduce exactamente el payload que reventaba."""
    r = ChatResponse(
        respuesta="Te dejé la acción lista para confirmar.",
        accion_dispositivo={
            "tipo": "pc_accion",
            "datos": {"accion": "abrir_app", "args": {"nombre": "spotify"}},
            "resumen": "Abrir «spotify» en tu PC.",
            "requiere_confirmacion": True,
        },
    )
    assert r.accion_dispositivo is not None


def test_todos_los_tipos_emitidos_estan_en_el_literal():
    """Inventario: cada `tipo` que el código emite en bloques accion_dispositivo
    está permitido por el Literal del schema. Si se agrega un emisor nuevo,
    actualizar AMBOS lados (o este test te frena antes que producción)."""
    emitidos = {
        "mensaje", "llamada", "evento", "abrir", "galeria", "pantalla",
        "whatsapp", "pc_accion",
    }
    literal = set(get_args(AccionDispositivo.model_fields["tipo"].annotation))
    faltan = emitidos - literal
    assert not faltan, f"tipos emitidos sin schema (serían 500): {faltan}"


# ── 2) Ruteo multi-paso → 6.3 ────────────────────────────────────────────────


def _desc(nombre: str) -> str:
    for t in tools.TOOL_DEFINITIONS:
        if t.get("function", {}).get("name") == nombre:
            return t["function"]["description"]
    raise AssertionError(f"tool {nombre} no está en el catálogo")


def test_descripcion_de_abrir_app_apunta_al_control_para_multipaso():
    d = _desc("pc_abrir_app")
    assert "pc_controlar_pantalla" in d  # «…y hacer algo DENTRO» → 6.3


def test_descripcion_de_control_no_invita_a_rehusar():
    d = _desc("pc_controlar_pantalla")
    # Debe vender el caso multi-paso y prohibir el «solo puedo abrir la app».
    assert "MULTI-PASO" in d or "multi-paso" in d
    assert "solo puedes abrir apps" in d or "solo puedo abrir" in d.lower()
    # Y no pre-rehusar por el estado del toggle: la tool reporta el motivo.
    assert "No asumas" in d


# ── 3) Autoconocimiento: sección PC generada del catálogo ────────────────────


def test_seccion_pc_cubre_todo_el_catalogo():
    seccion = capacidades_pc.seccion_capacidades_pc()
    nombres = [f["name"] for f in capacidades_pc.tools_pc()]
    assert nombres, "no hay tools pc_* en el catálogo (¿se renombraron?)"
    faltantes = [n for n in nombres if f"`{n}`" not in seccion]
    assert not faltantes, f"tools de PC sin describir en el prompt: {faltantes}"


def test_seccion_pc_trae_ruteo_y_rieles():
    s = capacidades_pc.seccion_capacidades_pc()
    # Ruteo: multi-paso → 6.3, y la frase prohibida de la era 6.2.
    assert "pc_controlar_pantalla" in s
    assert "MULTI-PASO" in s or "multi-paso" in s.lower()
    assert "no controlarla por dentro" in s.lower() or "controlarlas" in s.lower() \
        or "controlar" in s.lower()
    # Límites verdaderos: allowlist/denylist, confirmación, kill switch.
    assert "allowlist" in s and "denylist" in s.lower()
    assert "confirmaci" in s.lower()
    assert "kill switch" in s.lower()


def test_system_prompt_incluye_la_seccion_pc():
    """La sección viaja de verdad en el prompt fijo (y con la nota de que
    MANDA sobre texto viejo)."""
    from app.matix.system_prompt import system_prompt_fijo

    prompt = system_prompt_fijo()
    assert "CAPACIDADES EN LA PC" in prompt
    assert "pc_controlar_pantalla" in prompt
