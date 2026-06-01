"""ESTADO DE MATIX — la fuente de verdad sobre sí mismo.

El LLM no sabe los cambios de código por su cuenta: este bloque, inyectado en
el system prompt de cada turno, le dice quién es AHORA (versión, qué puede
hacer, últimos cambios) y en qué modelo está respondiendo. Así contesta con
precisión cuando le preguntan «¿qué puedes hacer?», «¿en qué modelo estás?» o
«¿cuál fue tu última actualización?».

Mantenerlo CORTO (no inflar tokens) y ACTUALIZARLO al shippear: subir
`VERSION`/`ACTUALIZADO`, ajustar capacidades si cambian, y dejar 2-3 cambios
recientes en `ULTIMOS_CAMBIOS`. La línea del modelo es dinámica (la arma
`chat.py` con el modelo que resolvió para ESE mensaje).
"""
from __future__ import annotations

# ── Editar al shippear ──────────────────────────────────────────────
VERSION = "2026.06"
ACTUALIZADO = "1 de junio de 2026"  # hora de Lima

# Capacidades actuales, en una línea compacta.
_CAPACIDADES = (
    "organiza tareas, proyectos, universidad (cursos, entregas, exámenes, "
    "apuntes), calendario y eventos, finanzas y apuntes; memoria personal "
    "duradera; lee imágenes y documentos (PDF/DOCX/TXT), transcribe audio y "
    "hace OCR por cámara; modos (tesis, estudio, motivación); recordatorios y "
    "avisos por push."
)

# Lo más reciente que shippeó (2-3 ítems). Sirve para «¿qué hay de nuevo?».
ULTIMOS_CAMBIOS = (
    "selector de modelo (OpenAI y Anthropic) con modo Automático que elige el "
    "modelo por mensaje; menú de adjuntar en el chat (documento, foto, cámara, "
    "audio, contacto); el historial ya sobrevive al cambio de modelo entre "
    "proveedores."
)


def _linea_modelo(*, modelo_id: str, modelo_etiqueta: str, auto: bool) -> str:
    base = f"Modelo actual: {modelo_etiqueta} (id {modelo_id})."
    if auto:
        base += (
            " El usuario tiene el modo Automático activo; para ESTE mensaje "
            f"elegiste {modelo_etiqueta}. Si te preguntan, dilo así: estás en "
            f"Automático y para esto usaste {modelo_etiqueta}."
        )
    return base


def bloque_estado(*, modelo_id: str, modelo_etiqueta: str, auto: bool) -> str:
    """El bloque `system` con el estado de Matix + el modelo de ESTE turno."""
    return (
        "ESTADO DE MATIX (la verdad sobre ti mismo; úsalo si te preguntan qué "
        "puedes hacer, en qué modelo estás o tu última actualización. No lo "
        "recites entero salvo que venga al caso):\n"
        f"- Versión {VERSION}, actualizado el {ACTUALIZADO}.\n"
        f"- {_linea_modelo(modelo_id=modelo_id, modelo_etiqueta=modelo_etiqueta, auto=auto)}\n"
        "- La voz (dictado y lectura) y la búsqueda en tus apuntes y memoria "
        "usan SIEMPRE OpenAI, sin importar el modelo de chat.\n"
        f"- Qué puedes hacer: {_CAPACIDADES}\n"
        f"- Últimos cambios: {ULTIMOS_CAMBIOS}"
    )
