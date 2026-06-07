"""Filtrado de tools por turno: no mandar las 93 definiciones al modelo en
cada mensaje, solo las que el turno puede necesitar.

DISEÑO CONSERVADOR (no perder potencia):
  - Un CORE siempre presente: CRUD del hub, consultas (read), memoria, RAG de
    apuntes, navegación/UX, web, proyectos básicos. Cubre el grueso de los
    turnos sin riesgo.
  - GRUPOS especializados (finanzas, árbol/intake de proyecto, planificador/
    horario, automatizaciones, teléfono, PC) que entran SOLO si el mensaje los
    dispara por palabra clave, o si el turno es "pesado"/ambiguo (entonces se
    mandan TODAS, para no recortar potencia donde el juicio importa).

Es PURO (sin BD, sin red): recibe el mensaje + las defs completas y devuelve el
subconjunto. Fácil de testear.
"""
from __future__ import annotations

import re
import unicodedata

# ── CORE: siempre presente (general-purpose). ────────────────────────────────
CORE: frozenset[str] = frozenset({
    # CRUD del hub
    "crear_tarea", "crear_tareas", "crear_evento", "crear_apunte",
    "editar_tarea", "editar_evento", "editar_apunte",
    "completar_tarea", "reabrir_tarea",
    "eliminar_tarea", "eliminar_evento", "eliminar_apunte",
    "marcar_accion_siguiente_hecha", "registrar_cierre",
    # Proyectos básicos (crear/estado; lo avanzado va en su grupo)
    "crear_proyecto", "editar_proyecto", "aparcar_proyecto",
    "terminar_proyecto", "reactivar_proyecto", "eliminar_proyecto",
    # Consultas (read) — baratas y de uso constante
    "consultar_tareas", "consultar_eventos", "consultar_proyectos",
    "consultar_apuntes", "consultar_movimientos", "consultar_uso",
    "consultar_gasto",
    # Memoria + RAG de apuntes + historial
    "recordar", "actualizar_memoria", "olvidar", "buscar_memoria",
    "buscar_apuntes", "leer_apunte", "buscar_en_historial",
    # UX + meta + web
    "navegar", "preguntar_con_opciones", "activar_modo", "desactivar_modo",
    "buscar_web", "obtener_cambios_recientes",
})

# ── GRUPOS especializados: (tools, patrón de disparo). ───────────────────────
_GRUPOS: list[tuple[frozenset[str], re.Pattern[str]]] = [
    # Finanzas
    (frozenset({
        "crear_movimiento", "registrar_movimientos", "revertir_ultimo_lote",
        "editar_movimiento", "eliminar_movimiento",
    }), re.compile(
        r"\b(gast|pagu?e?|pago|compr|plata|sol(es)?|s/|yape|plin|ingres|sueldo|"
        r"movimiento|factura|recibo|boleta|dinero|ahorr|presupuesto|deuda|"
        r"cobr|transferenci)\w*")),
    # Árbol / intake / perfil profundo de proyecto
    (frozenset({
        "ver_perfil_proyecto", "actualizar_perfil_proyecto",
        "anotar_detalle_proyecto", "corregir_detalle_proyecto",
        "borrar_detalle_proyecto", "iniciar_entrevista_proyecto",
        "continuar_entrevista_proyecto", "generar_arbol_proyecto",
        "ver_arbol_proyecto", "agregar_nodo", "actualizar_nodo",
        "eliminar_nodo", "refinar_fase", "avance_proyecto",
        "material_para_proyecto", "capacidad_proyectos",
        "importar_plan_proyecto", "intake_proyecto",
        "guardar_parametro_proyecto", "puede_planear_proyecto",
        "revisar_proyecto", "buscar_material",
    }), re.compile(
        r"\b(proyect|fase|arbol|nodo|intake|perfil|entrevista|descompon|"
        r"hito|avanc|meta|milestone|sprint|roadmap|material|biblioteca|"
        r"bloque|skill|curso)\w*")),
    # Planificador diario / horario
    (frozenset({
        "proponer_set_dia", "ver_set_dia", "aceptar_set_dia", "saltar_item_set",
        "configurar_planificacion", "plan_de_hoy", "replanificar_dia",
        "configurar_horario",
    }), re.compile(
        r"\b(set del dia|set de hoy|mi set|plan(ific)?|horario|replanific|"
        r"agenda|hueco|ventana|despert|dormir|ancla|rutina|pico|reorganiz|"
        r"acomod|que tengo hoy|que hago hoy|mi dia)\w*")),
    # Automatizaciones
    (frozenset({
        "crear_automatizacion", "listar_automatizaciones",
        "eliminar_automatizacion",
    }), re.compile(
        r"\b(automatiz|cada (dia|semana|lunes|manana)|todos los dias|"
        r"recurrent|programad|recordator|aviso|avisame|nudge)\w*")),
    # Teléfono (acciones de dispositivo)
    (frozenset({
        "redactar_mensaje", "iniciar_llamada", "crear_evento_telefono",
        "abrir_en_telefono", "leer_galeria", "leer_pantalla",
        "escribir_whatsapp",
    }), re.compile(
        r"\b(whatsapp|wasap|wsp|sms|correo|email|mail|llam|telefon|marca a|"
        r"abre|abri|lanza|galeri|ultima foto|pantalla|mapa|navega a|"
        r"mensaje a|escribele|mandale)\w*")),
    # PC / archivos (agente local)
    (frozenset({
        "pc_listar_carpeta", "pc_buscar_archivos", "pc_leer_archivo",
        "pc_resumir_documento", "pc_mover_archivo", "pc_renombrar_archivo",
        "pc_crear_carpeta", "pc_organizar_carpeta",
    }), re.compile(
        r"\b(archivo|carpeta|pc|compu|laptop|escritorio|descarga|"
        r"document|pdf|docx|\.txt|organiza|mueve|renombr|disco)\w*")),
]

# Si el mensaje es largo o "complejo", no arriesgamos potencia: van TODAS.
_UMBRAL_LARGO = 240
# Modos pesados (tesis/estudio): trabajo a fondo → todas las tools.
_MODOS_PESADOS: frozenset[str] = frozenset({"tesis", "estudio"})


def _norm(texto: str) -> str:
    s = unicodedata.normalize("NFD", (texto or "").lower())
    return "".join(c for c in s if unicodedata.category(c) != "Mn")


def nombres_relevantes(mensaje: str, *, modo: str | None = None) -> set[str] | None:
    """Conjunto de nombres de tools a mandar este turno, o None si deben ir
    TODAS (mensaje largo/ambiguo o modo pesado). PURO."""
    texto = _norm(mensaje)
    if modo in _MODOS_PESADOS:
        return None
    if len(texto) > _UMBRAL_LARGO:
        return None
    permitidos = set(CORE)
    for tools, patron in _GRUPOS:
        if patron.search(texto):
            permitidos |= tools
    return permitidos


def filtrar_tools(
    tools: list[dict], mensaje: str, *, modo: str | None = None
) -> list[dict]:
    """Devuelve el subconjunto de `tools` (formato OpenAI) relevante para el
    turno. Conserva el orden. Si corresponde mandar todas, devuelve `tools`
    tal cual. NUNCA devuelve menos que el CORE intersecado con el catálogo."""
    permitidos = nombres_relevantes(mensaje, modo=modo)
    if permitidos is None:
        return tools
    filtradas = [t for t in tools if t["function"]["name"] in permitidos]
    # Salvaguarda: si por lo que sea el filtro dejó muy poco (catálogo cambió),
    # cae a todas — jamás recortamos potencia por un bug del filtro.
    return filtradas if len(filtradas) >= len(CORE) // 2 else tools
