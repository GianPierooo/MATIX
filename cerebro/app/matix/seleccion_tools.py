"""Filtrado de tools por turno: no mandar las 124 definiciones al modelo en
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
    "marcar_accion_siguiente_hecha", "definir_accion_siguiente", "registrar_cierre",
    # Proyectos básicos (crear/estado; lo avanzado va en su grupo)
    "crear_proyecto", "editar_proyecto", "aparcar_proyecto",
    "terminar_proyecto", "reactivar_proyecto", "eliminar_proyecto",
    # Consultas (read) — baratas y de uso constante
    "consultar_tareas", "consultar_eventos", "consultar_proyectos",
    "consultar_apuntes", "consultar_movimientos", "consultar_uso",
    "consultar_gasto",
    # Universidad (read) — «¿qué cursos llevo?», «¿qué evaluaciones tengo?»
    "consultar_cursos", "consultar_sesiones_clase", "consultar_evaluaciones",
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
    # Universidad: cursos, sesiones de clase, evaluaciones (mutaciones)
    (frozenset({
        "crear_curso", "editar_curso", "eliminar_curso",
        "crear_sesion_clase", "crear_sesiones_clase", "editar_sesion_clase",
        "eliminar_sesion_clase", "crear_evaluacion", "editar_evaluacion",
        "eliminar_evaluacion",
    }), re.compile(
        r"\b(curso|materia|clase|profesor|universidad|\buni\b|facultad|ciclo|"
        r"semestre|examen|parcial|\bfinal(es)?\b|entrega|evaluacion|nota|"
        r"calificacion|silabo|syllabus|aula)\w*")),
    # Planificador diario / horario + bucle diario (bloques, despertar, rollover)
    (frozenset({
        "proponer_set_dia", "ver_set_dia", "aceptar_set_dia", "saltar_item_set",
        "configurar_planificacion", "plan_de_hoy", "replanificar_dia",
        "configurar_horario",
        "agendar_bloque", "saltar_bloque", "completar_bloque", "marcar_despertar",
        "proponer_rollover", "aplicar_rollover",
    }), re.compile(
        r"\b(set del dia|set de hoy|mi set|plan(ific)?|horario|replanific|"
        r"agenda|hueco|ventana|despert|levant|dormir|ancla|rutina|pico|reorganiz|"
        r"acomod|que tengo hoy|que hago hoy|mi dia|bloque|reprogram|pospon|"
        r"otro dia|suelt|no cumpl|no alcan|pendiente|vencid|retomar)\w*")),
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
    # PC / archivos / apps (agente local)
    (frozenset({
        "pc_listar_carpeta", "pc_buscar_archivos", "pc_leer_archivo",
        "pc_resumir_documento", "pc_mover_archivo", "pc_copiar_archivo",
        "pc_renombrar_archivo", "pc_crear_carpeta", "pc_organizar_carpeta",
        # 6.2 — abrir/cerrar apps y tareas tipadas
        "pc_abrir_app", "pc_ejecutar_tarea", "pc_cerrar_app",
        # Capacidades tipadas (librería confiable por tarea)
        "pc_abrir_carpeta", "pc_captura", "pc_crear_word", "pc_reproducir_spotify",
        "pc_control_spotify", "pc_abrir_web",
        # 6.3 — control autónomo de pantalla (último recurso)
        "pc_controlar_pantalla",
    }), re.compile(
        r"\b(archivo|carpeta|pc|compu|laptop|escritorio|descarga|"
        r"document|word|\.docx|pdf|docx|\.txt|organiza|mueve|copia|renombr|disco|"
        r"app|aplicacion|programa|abre|abrir|abri|lanza|cierra|cerrar|"
        r"foco|sesion|editor|vscode|chrome|navegador|spotify|cancion|musica|"
        r"reproduc|pausa|para la|siguiente|anterior|reanuda|sigue|pasala|salta|"
        r"captura|screenshot|pantallazo|web|url|pagina|sitio|"
        r"pantalla|control|mouse|raton|teclea|clic|click|haz por mi|hazlo tu)\w*")),
    # Subtareas + restaurar de papelera (gestión fina de tareas por IA).
    (frozenset({
        "crear_subtarea", "completar_subtarea", "eliminar_subtarea",
        "restaurar_tarea",
    }), re.compile(
        r"\b(subtarea|subtareas|sub-?tarea|checklist|restaura|restaurar|"
        r"recupera|recuperar|papelera)\w*"
        r"|de la papelera|borre por error|elimine por error|que borre|que elimine")),
]

# Si el mensaje es largo o "complejo", no arriesgamos potencia: van TODAS.
# 600 caracteres ≈ un párrafo largo. Por debajo, un turno conversacional normal
# (2-3 frases) se queda con el CORE + los grupos que dispare por keyword, sin
# volcar las 124 defs en CADA vuelta del loop (hasta _MAX_VUELTAS=6). Por encima
# de 600 asumimos multi-tema/complejo → todas, para no recortar potencia donde
# el juicio importa. Antes era 240, tan bajo que un mensaje de 2-3 frases ya
# volcaba el catálogo entero. (Umbral distinto del de enrutador._UMBRAL_LARGO=320,
# que elige el MODELO, no el set de tools — son decisiones independientes.)
_UMBRAL_LARGO = 600
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
    turno. Si corresponde mandar todas, devuelve `tools` tal cual. NUNCA devuelve
    menos que el CORE intersecado con el catálogo.

    ORDEN (B3, para cache-hit): CORE PRIMERO (en orden de catálogo) y luego los
    grupos disparados (en orden de catálogo). Así el bloque CORE es idéntico entre
    turnos aunque cambien los grupos → el prefijo se cachea (auto-cache de OpenAI;
    en Anthropic hay un breakpoint de cache al final del CORE, ver llm.py)."""
    permitidos = nombres_relevantes(mensaje, modo=modo)
    if permitidos is None:
        return tools
    core_first = [t for t in tools if t["function"]["name"] in CORE]
    resto = [
        t for t in tools
        if t["function"]["name"] in permitidos and t["function"]["name"] not in CORE
    ]
    filtradas = core_first + resto
    # Salvaguarda: si por lo que sea el filtro dejó muy poco (catálogo cambió),
    # cae a todas — jamás recortamos potencia por un bug del filtro.
    return filtradas if len(filtradas) >= len(CORE) // 2 else tools
