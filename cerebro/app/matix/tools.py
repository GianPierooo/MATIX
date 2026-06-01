"""Herramientas que Matix puede llamar (Capa 2 Paso 2).

Esta primera tanda es **solo aditiva o fácilmente reversible**: crear
tareas/eventos/apuntes, completar una tarea, registrar cierre del
día, marcar la acción siguiente de un proyecto como hecha. No están
las acciones de peso (aparcar/terminar proyectos, borrar) — eso
viene después, con confirmación explícita del usuario.

Estructura:

- `TOOL_DEFINITIONS` — los schemas JSON Schema que OpenAI necesita
  para hacer function calling. Lo único que `chat.py` le pasa al
  modelo.
- `ejecutar_tool(db, name, args)` — dispatcher. Devuelve un dict con
  el resultado serializable. El cerebro inyecta este dict como
  contenido del mensaje `tool` que va de vuelta al modelo.
- Cada handler interno usa el `Postgrest` directamente. No metemos
  HTTP entre nosotros (no tendría sentido — son la misma app). Las
  reglas que hoy viven en los routers (tope de 3 proyectos,
  coherencia acción siguiente↔proyecto, validación de Pydantic) se
  replican manualmente acá donde aplica — para esta tanda casi
  todas son aditivas y no necesitan reglas extra.

Filosofía del retorno:

- `{"ok": True, "datos": {...}}` cuando la acción tuvo éxito. `datos`
  es un resumen pequeño con lo mínimo para que el modelo confirme
  al usuario (título, id, fecha legible).
- `{"ok": False, "tipo": "...", "mensaje": "...", "sugerencia": "..."}`
  cuando hay un error esperable (id inexistente, conflicto de regla,
  validación). `tipo` es estable; `mensaje` y `sugerencia` están en
  español, redactados para que el modelo los pueda recitar tal cual
  o reformularlos. NUNCA un código HTTP crudo.
- Si hay una excepción inesperada (red, BD), el dispatcher la
  convierte en `{"ok": False, "tipo": "interno", "mensaje": "..."}`.

Tablas que cambian con cada tool (para que el chat invalide los
providers del Flutter):

    crear_tarea                 → ["tareas"]
    crear_evento                → ["eventos"]
    crear_apunte                → ["apuntes"]
    completar_tarea             → ["tareas"]
    marcar_accion_siguiente_hecha → ["tareas", "proyectos"]
    registrar_cierre            → ["cierres_dia"]
"""
from __future__ import annotations

import logging
import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Any
from uuid import UUID

import httpx
from pydantic import ValidationError

from ..db import Postgrest
from ..schemas.apuntes import ApunteCreate, ApunteUpdate
from ..schemas.cierres_dia import CierreDiaCreate
from ..schemas.eventos import EventoCreate, EventoUpdate
from ..schemas.movimientos import MovimientoCreate, MovimientoUpdate
from ..schemas.proyectos import ProyectoCreate, ProyectoUpdate
from ..schemas.tareas import TareaCreate, TareaUpdate
from . import finanzas, memoria, modos
from .biblioteca import buscar_material as _buscar_material_rag
from .indexador import buscar_apuntes as _buscar_apuntes_rag
from .indexador import indexar_apunte
from .uso import medidor

logger = logging.getLogger("matix.tools")

# ─────────────────────────────────────────────────────────────────────
# Schemas JSON Schema que OpenAI espera (tools=[...]).
# ─────────────────────────────────────────────────────────────────────

# Nota sobre fechas: pedimos ISO 8601 explícito con offset. El system
# prompt le aclara al modelo que Lima es UTC-5; aquí solo validamos
# que parsea, no la normalizamos.
_FECHA_HORA = {
    "type": "string",
    "description": (
        "Fecha y hora en ISO 8601 con offset, p.ej. "
        "`2026-05-27T08:00:00-05:00` (Lima es UTC-5)."
    ),
}

_UUID = {
    "type": "string",
    "description": "UUID exactamente como aparece en el contexto vivo.",
}

_PRIORIDAD = {
    "type": "string",
    "enum": ["alta", "media", "baja"],
    "description": "Prioridad de la tarea. Por defecto 'media'.",
}

# Parámetro `modo` de `activar_modo`: el enum se arma desde los .md del
# repo (app/matix/modos/), así agregar un modo = agregar un .md, sin tocar
# este schema. Si por alguna razón no hay .md, omitimos el enum (string libre).
_MODOS_NOMBRES = [m["nombre"] for m in modos.listar_modos()]
_PARAM_MODO: dict[str, Any] = {
    "type": "string",
    "description": "Nombre del modo a activar.",
}
if _MODOS_NOMBRES:
    _PARAM_MODO["enum"] = _MODOS_NOMBRES


TOOL_DEFINITIONS: list[dict[str, Any]] = [
    {
        "type": "function",
        "function": {
            "name": "crear_tarea",
            "description": (
                "Crea una tarea en el hub. Úsala cuando el usuario "
                "pida 'agenda', 'apunta', 'agrega una tarea' o "
                "equivalente. Si la tarea pertenece a un proyecto, "
                "pasa el `proyecto_id` del contexto. Si es para un "
                "curso, pasa el `curso_id`."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "titulo": {
                        "type": "string",
                        "description": "Título corto y accionable.",
                    },
                    "vence_en": {
                        **_FECHA_HORA,
                        "description": (
                            "Cuándo vence. Opcional pero recomendable. "
                            + _FECHA_HORA["description"]
                        ),
                    },
                    "prioridad": _PRIORIDAD,
                    "nota": {
                        "type": "string",
                        "description": "Detalle libre, opcional.",
                    },
                    "proyecto_id": {
                        **_UUID,
                        "description": (
                            "Id del proyecto al que pertenece, si aplica."
                        ),
                    },
                    "curso_id": {
                        **_UUID,
                        "description": (
                            "Id del curso al que pertenece, si aplica."
                        ),
                    },
                    "categoria_id": {
                        **_UUID,
                        "description": "Id de categoría, opcional.",
                    },
                    "recordar_en": {
                        **_FECHA_HORA,
                        "description": (
                            "Cuándo recordarle al usuario. Opcional. "
                            "Si no se especifica, no se programa "
                            "notificación."
                        ),
                    },
                },
                "required": ["titulo"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "crear_tareas",
            "description": (
                "Crea VARIAS tareas de una sola vez (un lote), de forma "
                "confiable. Úsala cuando el usuario aprueba una lista — "
                "típico al armar las tareas de un bloque de material de "
                "aprendizaje. Pasa `proyecto_id` (o `curso_id`) UNA vez y "
                "aplica a todas; cada item puede sobrescribirlo. "
                "GUARDRAIL: propón el siguiente trozo DIGERIBLE (la próxima "
                "sesión o semana del bloque), NO todo el currículo. El lote "
                "tiene un tope; si te pasas, la tool te lo dice para que lo "
                "ofrezcas por partes."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "tareas": {
                        "type": "array",
                        "description": (
                            "Lista de tareas a crear. Cada una es accionable "
                            "y concreta."
                        ),
                        "items": {
                            "type": "object",
                            "properties": {
                                "titulo": {
                                    "type": "string",
                                    "description": "Título corto y accionable.",
                                },
                                "vence_en": _FECHA_HORA,
                                "prioridad": _PRIORIDAD,
                                "nota": {"type": "string"},
                                "proyecto_id": _UUID,
                                "curso_id": _UUID,
                                "categoria_id": _UUID,
                                "recordar_en": _FECHA_HORA,
                            },
                            "required": ["titulo"],
                            "additionalProperties": False,
                        },
                    },
                    "proyecto_id": {
                        **_UUID,
                        "description": (
                            "Proyecto al que van TODAS las tareas del lote "
                            "(p.ej. el proyecto de la skill). Cada item lo "
                            "puede sobrescribir."
                        ),
                    },
                    "curso_id": {
                        **_UUID,
                        "description": "Curso para TODAS, si aplica.",
                    },
                    "categoria_id": {
                        **_UUID,
                        "description": "Categoría para TODAS, si aplica.",
                    },
                },
                "required": ["tareas"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "crear_evento",
            "description": (
                "Agenda un evento en el calendario. NO usar para "
                "clases recurrentes (esas son sesiones de clase, "
                "gestionadas desde Universidad)."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "titulo": {"type": "string"},
                    "inicia_en": _FECHA_HORA,
                    "termina_en": {
                        **_FECHA_HORA,
                        "description": (
                            "Hora de fin. Opcional. Si no se "
                            "especifica, el evento se pinta solo "
                            "con su hora de inicio."
                        ),
                    },
                    "descripcion": {"type": "string"},
                    "ubicacion": {"type": "string"},
                    "curso_id": _UUID,
                    "proyecto_id": _UUID,
                    "todo_el_dia": {
                        "type": "boolean",
                        "description": (
                            "True si es un evento de día completo. "
                            "Por defecto False."
                        ),
                    },
                    "recordar_en": _FECHA_HORA,
                },
                "required": ["titulo", "inicia_en"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "crear_apunte",
            "description": (
                "Crea un apunte (nota). Úsalo cuando el usuario pida "
                "'apunta', 'anota esto', 'guárdame esto', o dicte una "
                "idea para registrar. El contenido puede tener saltos "
                "de línea. Si la idea encaja CLARAMENTE con un proyecto "
                "activo o un curso que YA existe en el contexto vivo, "
                "etiquétalo pasando su `proyecto_id` y/o `curso_id`. Si "
                "no encaja claro con ninguno, déjalo general (sin "
                "ninguno de los dos). NUNCA inventes ni crees un "
                "proyecto o curso para poder clasificar."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "titulo": {"type": "string"},
                    "contenido": {
                        "type": "string",
                        "description": "Cuerpo del apunte.",
                    },
                    "etiquetas": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": (
                            "Etiquetas cortas en minúscula, ej. "
                            "['cálculo', 'examen-2']."
                        ),
                    },
                    "curso_id": _UUID,
                    "proyecto_id": _UUID,
                    "cuaderno_id": _UUID,
                },
                "required": ["titulo", "contenido"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "completar_tarea",
            "description": (
                "Marca una tarea existente como hecha. Si tenía "
                "repetición, el sistema crea automáticamente la "
                "próxima instancia — no la crees tú."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "tarea_id": {
                        **_UUID,
                        "description": (
                            "Id de la tarea, tomado del contexto vivo."
                        ),
                    },
                },
                "required": ["tarea_id"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "reabrir_tarea",
            "description": (
                "Reabre una tarea que estaba marcada como completada — "
                "la vuelve a pendiente. Es el inverso de "
                "`completar_tarea`. Úsalo cuando el usuario diga "
                "«reabre», «deshaz», «marca X como pendiente otra "
                "vez» o equivalente — típicamente después de un "
                "completar_tarea accidental (por ejemplo por una "
                "transcripción de voz mal entendida)."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "tarea_id": {
                        **_UUID,
                        "description": (
                            "Id de la tarea a reabrir. La vas a "
                            "encontrar en «Tareas completadas hoy» "
                            "del contexto vivo."
                        ),
                    },
                },
                "required": ["tarea_id"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "marcar_accion_siguiente_hecha",
            "description": (
                "Cuando el usuario diga «ya hice la acción siguiente "
                "de X» o equivalente, marca esa tarea como completada "
                "y limpia la acción siguiente del proyecto (queda "
                "vacía hasta que se defina una nueva)."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "proyecto_id": _UUID,
                },
                "required": ["proyecto_id"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "registrar_cierre",
            "description": (
                "Registra el cierre del día (ritual nocturno). "
                "Si la fecha ya tiene cierre, se actualiza. Pásale "
                "las 3 cosas que sí hizo + nota opcional. Por "
                "defecto, fecha de hoy."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "items": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": (
                            "Lista de cosas que sí hizo. Idealmente 3."
                        ),
                    },
                    "nota_extra": {
                        "type": "string",
                        "description": "Descarga mental, opcional.",
                    },
                    "fecha": {
                        "type": "string",
                        "description": (
                            "Fecha del cierre en formato YYYY-MM-DD. "
                            "Si no se pasa, hoy en Lima."
                        ),
                    },
                },
                "required": ["items"],
                "additionalProperties": False,
            },
        },
    },
    # ─── Capa 2 Paso 5: capacidad total ────────────────────────────
    {
        "type": "function",
        "function": {
            "name": "editar_tarea",
            "description": (
                "Edita campos de una tarea existente. Pásale el "
                "`tarea_id` y SOLO los campos que quieres cambiar. Si "
                "el usuario pide reagendar, cambiar prioridad, mover "
                "a otro proyecto/curso, agregar o quitar una nota — "
                "es esta. Para completar/reabrir tienes tools "
                "dedicadas; no las uses aquí."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "tarea_id": _UUID,
                    "titulo": {"type": "string"},
                    "nota": {"type": "string"},
                    "vence_en": _FECHA_HORA,
                    "prioridad": _PRIORIDAD,
                    "proyecto_id": _UUID,
                    "curso_id": _UUID,
                    "categoria_id": _UUID,
                    "recordar_en": _FECHA_HORA,
                },
                "required": ["tarea_id"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "eliminar_tarea",
            "description": (
                "Manda una tarea a la papelera. Es reversible: el "
                "usuario puede restaurar desde la app. Úsala cuando "
                "diga «borra esa tarea», «sácala», «elimínala». "
                "No es destructivo."
            ),
            "parameters": {
                "type": "object",
                "properties": {"tarea_id": _UUID},
                "required": ["tarea_id"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "editar_evento",
            "description": (
                "Edita campos de un evento existente. Pásale el "
                "`evento_id` y SOLO los campos que cambian. Útil para "
                "reagendar o renombrar."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "evento_id": _UUID,
                    "titulo": {"type": "string"},
                    "descripcion": {"type": "string"},
                    "inicia_en": _FECHA_HORA,
                    "termina_en": _FECHA_HORA,
                    "ubicacion": {"type": "string"},
                    "curso_id": _UUID,
                    "proyecto_id": _UUID,
                    "todo_el_dia": {"type": "boolean"},
                    "recordar_en": _FECHA_HORA,
                },
                "required": ["evento_id"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "eliminar_evento",
            "description": (
                "Manda un evento a la papelera (reversible)."
            ),
            "parameters": {
                "type": "object",
                "properties": {"evento_id": _UUID},
                "required": ["evento_id"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "editar_apunte",
            "description": (
                "Edita un apunte existente. Pásale el `apunte_id` y "
                "los campos que cambian. Útil para anexar contenido, "
                "renombrar, mover a otro cuaderno, ajustar etiquetas."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "apunte_id": _UUID,
                    "titulo": {"type": "string"},
                    "contenido": {"type": "string"},
                    "etiquetas": {
                        "type": "array",
                        "items": {"type": "string"},
                    },
                    "curso_id": _UUID,
                    "proyecto_id": _UUID,
                    "cuaderno_id": _UUID,
                },
                "required": ["apunte_id"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "eliminar_apunte",
            "description": (
                "Manda un apunte a la papelera (reversible)."
            ),
            "parameters": {
                "type": "object",
                "properties": {"apunte_id": _UUID},
                "required": ["apunte_id"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "crear_proyecto",
            "description": (
                "Crea un proyecto. Por defecto entra como `activo`. "
                "Si ya hay 3 activos, la operación falla con un "
                "mensaje que tienes que traducir al usuario: «ya tienes "
                "3 proyectos activos, aparca o termina uno primero». "
                "Para crear directo como aparcado o terminado, pasa "
                "`estado` correspondiente."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "nombre": {"type": "string"},
                    "descripcion": {"type": "string"},
                    "estado": {
                        "type": "string",
                        "enum": ["activo", "aparcado", "terminado"],
                    },
                    "linea_meta": {
                        "type": "string",
                        "description": (
                            "Definición clara de cuándo el proyecto "
                            "está «terminado»."
                        ),
                    },
                    "color": {"type": "string"},
                },
                "required": ["nombre"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "editar_proyecto",
            "description": (
                "Edita campos de un proyecto existente. Pásale el "
                "`proyecto_id` y los campos que cambian. NO cambies "
                "`estado` por aquí — usa `aparcar_proyecto`, "
                "`terminar_proyecto` o `reactivar_proyecto` que tienen "
                "la lógica del tope de 3."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "proyecto_id": _UUID,
                    "nombre": {"type": "string"},
                    "descripcion": {"type": "string"},
                    "linea_meta": {"type": "string"},
                    "color": {"type": "string"},
                },
                "required": ["proyecto_id"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "aparcar_proyecto",
            "description": (
                "Cambia el estado del proyecto a `aparcado`. "
                "Reversible vía `reactivar_proyecto`."
            ),
            "parameters": {
                "type": "object",
                "properties": {"proyecto_id": _UUID},
                "required": ["proyecto_id"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "terminar_proyecto",
            "description": (
                "Cambia el estado del proyecto a `terminado`. "
                "Reversible vía `reactivar_proyecto`."
            ),
            "parameters": {
                "type": "object",
                "properties": {"proyecto_id": _UUID},
                "required": ["proyecto_id"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "reactivar_proyecto",
            "description": (
                "Vuelve el proyecto al estado `activo`. Si ya hay 3 "
                "activos, falla — traduce el mensaje al usuario "
                "(«ya tienes 3 activos, aparca o termina uno antes»)."
            ),
            "parameters": {
                "type": "object",
                "properties": {"proyecto_id": _UUID},
                "required": ["proyecto_id"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "buscar_apuntes",
            "description": (
                "Busca en los apuntes del usuario por SIGNIFICADO "
                "semántico (RAG). Úsala cuando el usuario pregunte "
                "por algo que podría estar en sus notas: «¿qué "
                "anoté sobre X?», «búscame mi resumen de Y», "
                "«cuéntame qué decía mi apunte de Z». Devuelve los "
                "apuntes más relevantes con título y un fragmento. "
                "Si la búsqueda no devuelve nada, dilo: NO "
                "inventes contenido."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "consulta": {
                        "type": "string",
                        "description": (
                            "Lo que se está buscando, en lenguaje "
                            "natural. Puedes expandir la pregunta "
                            "del usuario si lo ayuda, pero no la "
                            "reformules en tecnicismos — la "
                            "búsqueda semántica funciona mejor con "
                            "lenguaje similar al de los apuntes."
                        ),
                    },
                    "top_k": {
                        "type": "integer",
                        "description": (
                            "Cuántos apuntes traer (1 a 10). "
                            "Default 5. Súbelo solo si el usuario "
                            "pide explorar varios."
                        ),
                    },
                },
                "required": ["consulta"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "leer_apunte",
            "description": (
                "Trae el contenido COMPLETO de un apunte por id. "
                "Úsala después de `buscar_apuntes` cuando necesites "
                "el texto entero para resumir, generar preguntas o "
                "explicar — `buscar_apuntes` devuelve solo un "
                "fragmento (600 chars), `leer_apunte` te da todo. "
                "Si el usuario te da el nombre del apunte y no el id, "
                "primero búscalo con `buscar_apuntes` y después léelo."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "apunte_id": _UUID,
                },
                "required": ["apunte_id"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "buscar_material",
            "description": (
                "Busca en la BIBLIOTECA de material de aprendizaje "
                "(NO en los apuntes de ideas: es un store aparte). "
                "Es el material de los tracks, etiquetado por `skill` "
                "(ej. 'calistenia', 'ingles') y `bloque` (ej. "
                "'bloque_3'). Úsala cuando el usuario trabaje un track "
                "o pida material de estudio de un skill: «¿qué toca en "
                "el bloque 3 de calistenia?», «explícame el material de "
                "esta etapa». Filtra por skill y/o bloque para traer "
                "justo lo de esa parte. Si no devuelve nada, dilo: NO "
                "inventes el material."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "consulta": {
                        "type": "string",
                        "description": (
                            "Qué buscar dentro del material, en lenguaje "
                            "natural. Si solo quieres todo el material de "
                            "un bloque, una consulta corta tipo el tema "
                            "del bloque sirve."
                        ),
                    },
                    "skill": {
                        "type": "string",
                        "description": (
                            "Acota a un skill (la carpeta, ej. "
                            "'calistenia'). Úsalo casi siempre: el "
                            "usuario trabaja un track a la vez."
                        ),
                    },
                    "bloque": {
                        "type": "string",
                        "description": (
                            "Acota a un bloque concreto (ej. 'bloque_3'). "
                            "Útil para «el bloque N de <skill>»."
                        ),
                    },
                    "top_k": {
                        "type": "integer",
                        "description": "Cuántos trozos traer (1 a 10). Default 5.",
                    },
                },
                "required": ["consulta"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "consultar_uso",
            "description": (
                "Devuelve el consumo acumulado de la API de OpenAI "
                "desde que arrancó este proceso del cerebro: tokens "
                "(input/output/cached), llamadas, segundos de "
                "Whisper y costo estimado en USD. Es solo lectura, "
                "no modifica nada. Úsala cuando el usuario pregunte "
                "«cuánto he gastado», «cuánto consumí», «qué tan caro "
                "vas», etc."
            ),
            "parameters": {
                "type": "object",
                "properties": {},
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "consultar_tareas",
            "description": (
                "Consulta las tareas del hub con filtros (SOLO LECTURA). "
                "Úsala cuando el usuario pregunte por sus pendientes: "
                "«¿qué tengo de la tesis?», «¿qué vence esta semana?», "
                "«¿qué tareas tengo del curso X?». No incluye la papelera. "
                "Para `proyecto_id`/`curso_id` usa los uuid tal como "
                "aparecen en el contexto vivo. Si la pregunta abarca un "
                "período (esta semana, este mes), calcula `vence_desde` / "
                "`vence_hasta` con la fecha de hoy del contexto. RESUME los "
                "resultados en lenguaje natural; no vuelques la lista cruda."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "proyecto_id": {
                        "type": "string",
                        "description": "Filtra por proyecto (uuid del contexto vivo).",
                    },
                    "curso_id": {
                        "type": "string",
                        "description": "Filtra por curso (uuid del contexto vivo).",
                    },
                    "estado": {
                        "type": "string",
                        "enum": ["pendiente", "completada", "todas"],
                        "description": "Default 'pendiente' (lo que falta hacer).",
                    },
                    "vence_desde": {
                        "type": "string",
                        "description": (
                            "Fecha YYYY-MM-DD: solo tareas que vencen en o "
                            "después de este día."
                        ),
                    },
                    "vence_hasta": {
                        "type": "string",
                        "description": (
                            "Fecha YYYY-MM-DD: solo tareas que vencen hasta "
                            "este día (inclusive)."
                        ),
                    },
                },
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "consultar_eventos",
            "description": (
                "Consulta los eventos del calendario en un rango de fechas "
                "(SOLO LECTURA). Úsala para «¿qué eventos tengo esta "
                "semana?», «¿qué tengo el viernes?». No incluye la "
                "papelera. Calcula `desde`/`hasta` con la fecha de hoy del "
                "contexto. Los eventos recurrentes se devuelven por su "
                "fecha ancla con su regla; avísale al usuario que se "
                "repiten. RESUME, no vuelques la lista cruda."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "desde": {
                        "type": "string",
                        "description": "Fecha YYYY-MM-DD de inicio del rango (inclusive).",
                    },
                    "hasta": {
                        "type": "string",
                        "description": "Fecha YYYY-MM-DD de fin del rango (inclusive).",
                    },
                },
                "required": ["desde", "hasta"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "consultar_proyectos",
            "description": (
                "Consulta los proyectos del hub (SOLO LECTURA). Úsala para "
                "«¿qué proyectos tengo?», «¿cuáles están en riesgo?». "
                "`en_riesgo=true` devuelve solo los activos sin avance en "
                "3+ días. Filtra por estado si hace falta. RESUME en "
                "lenguaje natural."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "estado": {
                        "type": "string",
                        "enum": ["activo", "aparcado", "terminado", "todos"],
                        "description": "Default 'activo'.",
                    },
                    "en_riesgo": {
                        "type": "boolean",
                        "description": (
                            "Si true, solo los activos en riesgo (3+ días "
                            "sin actividad)."
                        ),
                    },
                },
                "additionalProperties": False,
            },
        },
    },
    # ── Apuntes: listado plano (sin RAG) ─────────────────────────────
    {
        "type": "function",
        "function": {
            "name": "consultar_apuntes",
            "description": (
                "Lista los apuntes del hub por título (SOLO LECTURA, sin "
                "búsqueda semántica). Úsala para ENUMERAR apuntes y obtener "
                "sus `apunte_id` cuando el usuario quiere editar o BORRAR uno "
                "por su nombre (p.ej. «borra mi apunte de la lista de "
                "compras»). Si pasas `texto`, filtra por coincidencia en el "
                "título. Para buscar por SIGNIFICADO usa `buscar_apuntes`."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "texto": {
                        "type": "string",
                        "description": (
                            "Filtro opcional: subcadena a buscar en el "
                            "título (sin distinguir mayúsculas)."
                        ),
                    },
                },
                "additionalProperties": False,
            },
        },
    },
    # ── Finanzas: movimientos (CRUD completo) ────────────────────────
    {
        "type": "function",
        "function": {
            "name": "crear_movimiento",
            "description": (
                "Registra un movimiento de finanzas: un ingreso o un gasto. "
                "El `monto` SIEMPRE es positivo; el signo lo da `tipo`. Si no "
                "te dan fecha, se usa hoy. Categoría libre (p.ej. «Comida», "
                "«Transporte», «Sueldo»); por defecto «General»."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "tipo": {
                        "type": "string",
                        "enum": ["ingreso", "gasto"],
                    },
                    "monto": {
                        "type": "number",
                        "description": "Monto positivo en soles (S/).",
                    },
                    "categoria": {"type": "string"},
                    "fecha": {
                        "type": "string",
                        "description": "Fecha ISO `YYYY-MM-DD`. Opcional.",
                    },
                    "nota": {"type": "string"},
                },
                "required": ["tipo", "monto"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "consultar_movimientos",
            "description": (
                "Consulta los movimientos de finanzas (SOLO LECTURA). "
                "Devuelve los más recientes con su balance, ingresos y "
                "gastos. Filtra por `tipo` si hace falta. RESUME en lenguaje "
                "natural (no vuelques la tabla cruda)."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "tipo": {
                        "type": "string",
                        "enum": ["ingreso", "gasto", "todos"],
                        "description": "Default 'todos'.",
                    },
                },
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "editar_movimiento",
            "description": (
                "Edita un movimiento existente. Pásale el `movimiento_id` "
                "(de `consultar_movimientos`) y solo los campos que cambian."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "movimiento_id": _UUID,
                    "tipo": {
                        "type": "string",
                        "enum": ["ingreso", "gasto"],
                    },
                    "monto": {"type": "number"},
                    "categoria": {"type": "string"},
                    "fecha": {"type": "string"},
                    "nota": {"type": "string"},
                },
                "required": ["movimiento_id"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "eliminar_movimiento",
            "description": (
                "Borra UN movimiento concreto por su `movimiento_id`. OJO: es "
                "PERMANENTE (no hay papelera para finanzas). Úsala solo para un "
                "registro específico; para deshacer lo último que registraste, "
                "usa `revertir_ultimo_lote`."
            ),
            "parameters": {
                "type": "object",
                "properties": {"movimiento_id": _UUID},
                "required": ["movimiento_id"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "registrar_movimientos",
            "description": (
                "Registra VARIOS movimientos de una imagen (Yape/banco/recibo) "
                "en un solo lote. Flujo de DOS pasos para no meter datos malos:\n"
                "1) Primero llámala con `confirmado=false` (o sin él): NO "
                "escribe nada, te devuelve la lista CLASIFICADA (preview) para "
                "que se la muestres al usuario y le pidas confirmar.\n"
                "2) Solo cuando el usuario confirme, llámala con "
                "`confirmado=true` para registrarlos.\n"
                "Cada item: `tipo` (gasto/ingreso), `monto` positivo, y la "
                "`senal` que VISTE en la imagen (el signo o la palabra: «-30», "
                "«+50», «Pagaste», «Te yapearon», «rojo»…) — la uso para "
                "verificar la clasificación. Respeta el filtro del usuario con "
                "`filtro`: si pidió «solo los gastos», pasa `filtro='solo_gastos'` "
                "y descarto los ingresos. Para UN movimiento simple usa "
                "`crear_movimiento`, no esto."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "movimientos": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "tipo": {
                                    "type": "string",
                                    "enum": ["ingreso", "gasto"],
                                },
                                "monto": {"type": "number"},
                                "categoria": {"type": "string"},
                                "fecha": {"type": "string"},
                                "nota": {"type": "string"},
                                "senal": {
                                    "type": "string",
                                    "description": (
                                        "Lo que viste que indica el tipo: signo "
                                        "(-/+), color o palabra (Pagaste, "
                                        "Recibiste, Abono…)."
                                    ),
                                },
                            },
                            "required": ["tipo", "monto"],
                        },
                    },
                    "filtro": {
                        "type": "string",
                        "enum": ["todos", "solo_gastos", "solo_ingresos"],
                        "description": "Default 'todos'. Respeta lo que pidió el usuario.",
                    },
                    "confirmado": {
                        "type": "boolean",
                        "description": "false = preview (no escribe); true = registra.",
                    },
                },
                "required": ["movimientos"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "revertir_ultimo_lote",
            "description": (
                "Deshace el ÚLTIMO lote de movimientos que registraste (uno "
                "suelto o un grupo de una imagen). Borra SOLO esos; nunca toca "
                "movimientos buenos no relacionados ni los que el usuario creó a "
                "mano. Úsala cuando diga «revierte», «corrige eso», «bórralos». "
                "Dos pasos: primero con `confirmado=false` para mostrar qué "
                "borrarías; solo con `confirmado=true` cuando el usuario acepte."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "confirmado": {
                        "type": "boolean",
                        "description": "false = preview (no borra); true = borra el lote.",
                    },
                },
                "additionalProperties": False,
            },
        },
    },
    # ── Navegación: llevar al usuario a una sección de la app ─────────
    {
        "type": "function",
        "function": {
            "name": "navegar",
            "description": (
                "Lleva al usuario a una sección de la app cuando lo pide "
                "(«llévame a Universidad», «abre Finanzas», «vamos a "
                "Tareas»). NO cambia datos: solo abre la pantalla. Después "
                "confírmalo en una frase corta («Listo, te llevo a "
                "Universidad»)."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "seccion": {
                        "type": "string",
                        "enum": [
                            "inicio",
                            "tareas",
                            "calendario",
                            "proyectos",
                            "universidad",
                            "finanzas",
                            "apuntes",
                            "ajustes",
                        ],
                    },
                },
                "required": ["seccion"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "preguntar_con_opciones",
            "description": (
                "Hace una pregunta y ofrece opciones TOCABLES (chips/botones) o "
                "un campo de texto, para que el usuario elija sin escribir todo. "
                "Úsala cuando ofrecer una ELECCIÓN o pedir una PREFERENCIA "
                "ayuda: «¿qué modo activo?», «¿corto/medio/largo plazo?», «¿cuál "
                "de estos cursos?», «¿prefieres A o B?». Tu cierre con gancho "
                "puede venir como opciones. NO la uses para respuestas abiertas "
                "ni para todo: solo cuando un conjunto chico y claro de opciones "
                "(o un dato puntual) hace más fácil responder.\n"
                "El turno TERMINA al usarla: la `pregunta` es el mensaje y las "
                "opciones se pintan debajo; el usuario responde tocando."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "pregunta": {
                        "type": "string",
                        "description": "La pregunta, en tu voz (será el mensaje).",
                    },
                    "tipo": {
                        "type": "string",
                        "enum": [
                            "seleccion_unica",
                            "seleccion_multiple",
                            "texto",
                        ],
                        "description": (
                            "seleccion_unica = elegir una; seleccion_multiple = "
                            "varias; texto = un campo para escribir."
                        ),
                    },
                    "opciones": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": (
                            "Las opciones (2 a 6, cortas). Vacío si tipo=texto."
                        ),
                    },
                },
                "required": ["pregunta", "tipo"],
                "additionalProperties": False,
            },
        },
    },
    # ── Modos de Matix (tono + conocimiento + prioridades) ───────────
    {
        "type": "function",
        "function": {
            "name": "activar_modo",
            "description": (
                "Activa un MODO de Matix, que ajusta tu tono, tu conocimiento "
                "y tus prioridades. Úsalo cuando el usuario lo pida ('ponte en "
                "modo tesis') O cuando DETECTES el contexto (habla de su tesis, "
                "de estudiar, está desanimado y necesita empuje). REGLA: "
                "SIEMPRE avísale en una frase corta que lo activaste ('Activé "
                "el modo tesis, te ayudo con eso'); NUNCA cambies de modo en "
                "silencio. El modo se queda activo hasta que lo cambies o lo "
                "apagues con `desactivar_modo`."
            ),
            "parameters": {
                "type": "object",
                "properties": {"modo": _PARAM_MODO},
                "required": ["modo"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "desactivar_modo",
            "description": (
                "Vuelve al modo NORMAL (sin modo). Úsalo cuando el usuario diga "
                "'sal del modo', 'modo normal', o cuando el tema del modo "
                "claramente terminó y conviene volver a lo general. Avísale en "
                "una frase corta que volviste a normal."
            ),
            "parameters": {
                "type": "object",
                "properties": {},
                "additionalProperties": False,
            },
        },
    },
    # ── Memoria personal (lo que Matix sabe del usuario) ─────────────
    {
        "type": "function",
        "function": {
            "name": "recordar",
            "description": (
                "Guarda un HECHO DURADERO sobre el usuario en la memoria "
                "personal (quién es, sus metas, personas importantes, su "
                "situación, preferencias, contexto de sus proyectos). Úsalo "
                "cuando diga 'recuerda que…' O cuando cuente algo estable que "
                "valga la pena recordar para personalizar. NO guardes cosas "
                "efímeras (una tarea de hoy va a `crear_tarea`, no acá). "
                "Confírmalo en una frase corta ('Anotado, lo recordaré'). "
                "`esencial=true` (default) lo inyecto siempre; ponlo en false "
                "para detalle largo que solo hace falta a veces."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "contenido": {
                        "type": "string",
                        "description": "El hecho, en una o pocas frases.",
                    },
                    "categoria": {
                        "type": "string",
                        "description": (
                            "Para organizar: quien_soy, metas, personas, "
                            "situacion, preferencias, proyectos… Opcional."
                        ),
                    },
                    "esencial": {
                        "type": "boolean",
                        "description": "Si va siempre en el contexto. Default true.",
                    },
                },
                "required": ["contenido"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "actualizar_memoria",
            "description": (
                "Actualiza un hecho de la memoria (cambió una meta, una "
                "situación). Pásale el `memoria_id` (de `buscar_memoria`) y lo "
                "que cambia."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "memoria_id": _UUID,
                    "contenido": {"type": "string"},
                    "categoria": {"type": "string"},
                    "esencial": {"type": "boolean"},
                },
                "required": ["memoria_id"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "olvidar",
            "description": (
                "Borra un hecho de la memoria (PERMANENTE, sin papelera). Úsalo "
                "cuando el usuario diga 'olvida que…'. Si no tienes el "
                "`memoria_id`, primero `buscar_memoria` para encontrarlo. "
                "Confírmalo ('Listo, lo olvidé')."
            ),
            "parameters": {
                "type": "object",
                "properties": {"memoria_id": _UUID},
                "required": ["memoria_id"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "buscar_memoria",
            "description": (
                "Busca en la memoria personal por SIGNIFICADO (SOLO LECTURA). "
                "Lo esencial ya lo tienes inyectado en «lo que sé de ti»; usa "
                "esto para recuperar detalle que NO esté en ese bloque, o para "
                "obtener el `memoria_id` antes de actualizar/olvidar un hecho."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "consulta": {
                        "type": "string",
                        "description": "Qué buscar, en lenguaje natural.",
                    },
                },
                "required": ["consulta"],
                "additionalProperties": False,
            },
        },
    },
]


# ─────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────


def _hoy_lima() -> date:
    return datetime.now(timezone.utc).astimezone(
        timezone(timedelta(hours=-5))
    ).date()


def _ok(datos: dict[str, Any]) -> dict[str, Any]:
    return {"ok": True, "datos": datos}


def _error(
    tipo: str, mensaje: str, *, sugerencia: str | None = None
) -> dict[str, Any]:
    out: dict[str, Any] = {"ok": False, "tipo": tipo, "mensaje": mensaje}
    if sugerencia:
        out["sugerencia"] = sugerencia
    return out


def _err_validacion(e: ValidationError) -> dict[str, Any]:
    """Traduce un error de Pydantic a un mensaje legible para el
    modelo. No queremos exponer el formato técnico de Pydantic."""
    errs = e.errors()
    if errs:
        primer = errs[0]
        campo = ".".join(str(x) for x in primer.get("loc", []))
        msg = primer.get("msg", "valor inválido")
        return _error(
            "validacion",
            f"Campo «{campo}» no es válido: {msg}.",
            sugerencia=(
                "Revisa el formato (fechas en ISO 8601, ids como UUID) "
                "y vuelve a llamarme."
            ),
        )
    return _error("validacion", "Hay un campo con valor inválido.")


def _resumen_fecha(iso: str | None) -> str | None:
    """Convierte un ISO 8601 a algo legible en hora Lima."""
    if iso is None:
        return None
    try:
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        lima = dt.astimezone(timezone(timedelta(hours=-5)))
        return lima.strftime("%a %d %b %H:%M")
    except Exception:
        return iso


# ─────────────────────────────────────────────────────────────────────
# Handlers — uno por tool
# ─────────────────────────────────────────────────────────────────────


async def _crear_tarea(db: Postgrest, args: dict) -> dict[str, Any]:
    try:
        body = TareaCreate(**args)
    except ValidationError as e:
        return _err_validacion(e)

    payload = body.model_dump(mode="json", exclude_none=True)
    fila = await db.insert("tareas", payload)
    return _ok(
        {
            "id": fila["id"],
            "titulo": fila["titulo"],
            "vence_en_legible": _resumen_fecha(fila.get("vence_en")),
            "prioridad": fila["prioridad"],
        }
    )


# Tope del lote: el guardrail "no vacíes todo el currículo". Si el modelo
# intenta crear más de esto de una, lo paramos y le pedimos que ofrezca el
# resto por partes (la próxima sesión/semana). A propósito: no enterrar al
# usuario en tareas.
_MAX_LOTE_TAREAS = 12


async def _crear_tareas(db: Postgrest, args: dict) -> dict[str, Any]:
    """Crea un lote de tareas en una sola acción. Valida TODAS antes de
    insertar ninguna (o se crea el lote válido entero, o se reporta el
    error sin crear nada a medias). Aplica los defaults de proyecto/curso/
    categoría a los items que no los traigan."""
    items = args.get("tareas")
    if not isinstance(items, list) or not items:
        return _error(
            "validacion",
            "Pásame `tareas`: una lista con al menos una tarea.",
        )
    if len(items) > _MAX_LOTE_TAREAS:
        return _error(
            "validacion",
            f"Son {len(items)} tareas de una — demasiadas. Propón el "
            f"siguiente trozo digerible (la próxima sesión o semana, hasta "
            f"{_MAX_LOTE_TAREAS}) y ofrece el resto por partes.",
        )

    # Defaults del lote: se aplican a cada item que no traiga el suyo.
    defaults = {
        k: args.get(k)
        for k in ("proyecto_id", "curso_id", "categoria_id")
        if args.get(k)
    }

    # 1) Validar TODAS primero — fail fast, sin crear nada a medias.
    validadas: list[dict[str, Any]] = []
    for i, item in enumerate(items):
        if not isinstance(item, dict):
            return _error(
                "validacion", f"La tarea #{i + 1} no es un objeto válido."
            )
        combinado = {**defaults, **item}
        try:
            body = TareaCreate(**combinado)
        except ValidationError as e:
            val = _err_validacion(e)
            val["mensaje"] = f"Tarea #{i + 1}: {val['mensaje']}"
            return val
        validadas.append(body.model_dump(mode="json", exclude_none=True))

    # 2) Insertar el lote completo.
    creadas: list[dict[str, Any]] = []
    for payload in validadas:
        fila = await db.insert("tareas", payload)
        creadas.append(
            {
                "id": fila["id"],
                "titulo": fila["titulo"],
                "vence_en_legible": _resumen_fecha(fila.get("vence_en")),
            }
        )
    return _ok(
        {
            "total": len(creadas),
            "proyecto_id": defaults.get("proyecto_id"),
            "tareas": creadas,
        }
    )


async def _crear_evento(db: Postgrest, args: dict) -> dict[str, Any]:
    try:
        body = EventoCreate(**args)
    except ValidationError as e:
        return _err_validacion(e)

    payload = body.model_dump(mode="json", exclude_none=True)
    fila = await db.insert("eventos", payload)
    return _ok(
        {
            "id": fila["id"],
            "titulo": fila["titulo"],
            "inicia_en_legible": _resumen_fecha(fila["inicia_en"]),
            "termina_en_legible": _resumen_fecha(fila.get("termina_en")),
        }
    )


async def _indexar_silencioso(db: Postgrest, apunte: dict) -> None:
    """Indexa el apunte para el RAG sin propagar fallos. El apunte ya
    quedó guardado; si el embedding falla (OpenAI caído, etc.) no
    rompemos la tool: el próximo edit o el backfill lo reintenta.
    Mismo criterio que `_reindexar_silencioso` del router de apuntes."""
    try:
        await indexar_apunte(db, apunte)
    except Exception:  # noqa: BLE001
        logger.exception("indexador falló para apunte %s", apunte.get("id"))


async def _destino_apunte(db: Postgrest, apunte: dict) -> dict[str, Any]:
    """Resuelve dónde quedó archivado el apunte (proyecto y/o curso,
    con nombre) para que Matix lo confirme en una línea. Un apunte sin
    proyecto ni curso es `general`. Devolvemos el nombre desde la BD
    para que el modelo no lo adivine."""
    out: dict[str, Any] = {}
    proyecto_id = apunte.get("proyecto_id")
    curso_id = apunte.get("curso_id")
    if proyecto_id:
        proyecto = await db.get("proyectos", str(proyecto_id))
        if proyecto:
            out["proyecto_nombre"] = proyecto.get("nombre")
    if curso_id:
        curso = await db.get("cursos", str(curso_id))
        if curso:
            out["curso_nombre"] = curso.get("nombre")
    out["general"] = not (out.get("proyecto_nombre") or out.get("curso_nombre"))
    return out


async def _crear_apunte(db: Postgrest, args: dict) -> dict[str, Any]:
    try:
        body = ApunteCreate(**args)
    except ValidationError as e:
        return _err_validacion(e)

    payload = body.model_dump(mode="json", exclude_none=True)
    fila = await db.insert("apuntes", payload)

    # Que quede buscable por el RAG, igual que cuando se crea desde la
    # app (Capa 3). No es crítico para la creación: si falla, el apunte
    # ya está guardado.
    await _indexar_silencioso(db, fila)

    datos: dict[str, Any] = {
        "id": fila["id"],
        "titulo": fila["titulo"],
        "etiquetas": fila.get("etiquetas", []),
    }
    datos.update(await _destino_apunte(db, fila))
    return _ok(datos)


async def _completar_tarea(db: Postgrest, args: dict) -> dict[str, Any]:
    raw_id = args.get("tarea_id")
    if not raw_id:
        return _error(
            "validacion",
            "Falta el `tarea_id`.",
            sugerencia="Mira el contexto vivo y vuelve a llamarme con el id.",
        )
    try:
        tarea_id = str(UUID(str(raw_id)))
    except (ValueError, TypeError):
        return _error(
            "validacion",
            f"El id «{raw_id}» no es un UUID válido.",
        )

    actual = await db.get("tareas", tarea_id)
    if actual is None:
        return _error(
            "no_existe",
            "Esa tarea ya no está en el hub (puede que la borraran).",
            sugerencia="Revisa la lista actualizada y vuelve a intentar.",
        )
    if actual.get("completada"):
        return _ok(
            {
                "id": tarea_id,
                "titulo": actual["titulo"],
                "ya_estaba_completada": True,
            }
        )

    ahora = datetime.now(timezone.utc).isoformat()
    fila = await db.update(
        "tareas",
        tarea_id,
        {"completada": True, "completada_en": ahora},
    )
    if fila is None:
        return _error(
            "interno",
            "No se pudo marcar la tarea (la BD no la devolvió).",
        )

    # Repetición: si la tarea tenía patrón y `vence_en`, crear la
    # próxima instancia. Replicamos la lógica del router de tareas
    # para mantener consistencia.
    if actual.get("repeticion") and actual.get("vence_en"):
        await _crear_siguiente_instancia(db, actual, actual["repeticion"])

    return _ok(
        {
            "id": tarea_id,
            "titulo": actual["titulo"],
            "repetida": bool(actual.get("repeticion")),
        }
    )


async def _reabrir_tarea(db: Postgrest, args: dict) -> dict[str, Any]:
    raw_id = args.get("tarea_id")
    if not raw_id:
        return _error(
            "validacion",
            "Falta el `tarea_id`.",
            sugerencia=(
                "Busca la tarea en «Tareas completadas hoy» del "
                "contexto y vuelve a llamarme con su id."
            ),
        )
    try:
        tarea_id = str(UUID(str(raw_id)))
    except (ValueError, TypeError):
        return _error(
            "validacion",
            f"El id «{raw_id}» no es un UUID válido.",
        )

    actual = await db.get("tareas", tarea_id)
    if actual is None:
        return _error(
            "no_existe",
            "Esa tarea ya no está en el hub (puede que la borraran).",
        )
    if not actual.get("completada"):
        return _ok(
            {
                "id": tarea_id,
                "titulo": actual["titulo"],
                "ya_estaba_pendiente": True,
            }
        )

    fila = await db.update(
        "tareas",
        tarea_id,
        {"completada": False, "completada_en": None},
    )
    if fila is None:
        return _error(
            "interno",
            "No se pudo reabrir la tarea (la BD no la devolvió).",
        )

    return _ok({"id": tarea_id, "titulo": actual["titulo"]})


async def _marcar_accion_siguiente_hecha(
    db: Postgrest, args: dict
) -> dict[str, Any]:
    raw_id = args.get("proyecto_id")
    if not raw_id:
        return _error("validacion", "Falta el `proyecto_id`.")
    try:
        proyecto_id = str(UUID(str(raw_id)))
    except (ValueError, TypeError):
        return _error(
            "validacion",
            f"El id «{raw_id}» no es un UUID válido.",
        )

    proyecto = await db.get("proyectos", proyecto_id)
    if proyecto is None:
        return _error(
            "no_existe",
            "Ese proyecto ya no está en el hub.",
        )

    tarea_sig_id = proyecto.get("tarea_siguiente_id")
    if not tarea_sig_id:
        return _error(
            "sin_accion_siguiente",
            (
                f"El proyecto «{proyecto['nombre']}» no tiene una "
                "acción siguiente definida ahora mismo."
            ),
            sugerencia=(
                "Dile al usuario que defina la próxima acción "
                "siguiente desde la app (Detalle del proyecto)."
            ),
        )

    tarea = await db.get("tareas", tarea_sig_id)
    if tarea is None:
        # Inconsistencia: el proyecto apunta a una tarea que no
        # existe. Limpiamos el puntero igual.
        await db.update(
            "proyectos",
            proyecto_id,
            {
                "tarea_siguiente_id": None,
                "ultima_actividad_en": datetime.now(timezone.utc).isoformat(),
            },
        )
        return _error(
            "inconsistencia",
            (
                "La acción siguiente apuntaba a una tarea que ya no "
                "existe. Limpié la referencia. Dile al usuario "
                "que defina una nueva."
            ),
        )

    ahora = datetime.now(timezone.utc).isoformat()
    if not tarea.get("completada"):
        await db.update(
            "tareas",
            tarea_sig_id,
            {"completada": True, "completada_en": ahora},
        )
        # repetición
        if tarea.get("repeticion") and tarea.get("vence_en"):
            await _crear_siguiente_instancia(db, tarea, tarea["repeticion"])

    await db.update(
        "proyectos",
        proyecto_id,
        {"tarea_siguiente_id": None, "ultima_actividad_en": ahora},
    )

    return _ok(
        {
            "proyecto_id": proyecto_id,
            "proyecto_nombre": proyecto["nombre"],
            "tarea_completada": tarea["titulo"],
        }
    )


async def _registrar_cierre(db: Postgrest, args: dict) -> dict[str, Any]:
    items = args.get("items")
    if not items or not isinstance(items, list):
        return _error(
            "validacion",
            "Faltan los `items` del cierre (al menos uno).",
        )

    fecha_arg = args.get("fecha")
    if fecha_arg:
        try:
            fecha_val = date.fromisoformat(fecha_arg)
        except ValueError:
            return _error(
                "validacion",
                f"La fecha «{fecha_arg}» no tiene formato YYYY-MM-DD.",
            )
    else:
        fecha_val = _hoy_lima()

    try:
        body = CierreDiaCreate(
            fecha=fecha_val,
            items=[str(x) for x in items],
            nota_extra=args.get("nota_extra"),
        )
    except ValidationError as e:
        return _err_validacion(e)

    payload = body.model_dump(mode="json", exclude_none=True)

    # UPSERT por fecha (mismo comportamiento que el router CRUD).
    existentes = await db.list(
        "cierres_dia",
        filters={"fecha": fecha_val.isoformat()},
        limit=1,
    )
    if existentes:
        actual = existentes[0]
        fila = await db.update("cierres_dia", actual["id"], payload) or actual
        sobreescrito = True
    else:
        fila = await db.insert("cierres_dia", payload)
        sobreescrito = False

    return _ok(
        {
            "id": fila["id"],
            "fecha": fila["fecha"],
            "n_items": len(fila.get("items") or []),
            "sobreescrito": sobreescrito,
        }
    )


# ── Editar / eliminar / restaurar — Capa 2 Paso 5 ──────────────────


def _validar_uuid(raw: Any, campo: str) -> tuple[str | None, dict | None]:
    """Helper: valida y normaliza un UUID. Devuelve `(uuid, None)` si
    ok, o `(None, error_dict)` para que el caller lo retorne tal cual."""
    if not raw:
        return None, _error("validacion", f"Falta el `{campo}`.")
    try:
        return str(UUID(str(raw))), None
    except (ValueError, TypeError):
        return None, _error(
            "validacion", f"El id «{raw}» no es un UUID válido."
        )


async def _editar_tarea(db: Postgrest, args: dict) -> dict[str, Any]:
    tarea_id, err = _validar_uuid(args.get("tarea_id"), "tarea_id")
    if err:
        return err
    # Sacamos `tarea_id` antes de validar con Pydantic.
    campos = {k: v for k, v in args.items() if k != "tarea_id"}
    if not campos:
        return _error(
            "validacion",
            "No me pasaste qué campo cambiar.",
            sugerencia="Vuelve a llamarme con al menos un campo además del id.",
        )
    try:
        body = TareaUpdate(**campos)
    except ValidationError as e:
        return _err_validacion(e)
    payload = body.model_dump(mode="json", exclude_unset=True)
    fila = await db.update("tareas", tarea_id, payload)
    if fila is None:
        return _error("no_existe", "Esa tarea ya no está en el hub.")
    return _ok(
        {
            "id": tarea_id,
            "titulo": fila["titulo"],
            "vence_en_legible": _resumen_fecha(fila.get("vence_en")),
        }
    )


async def _eliminar_tarea(db: Postgrest, args: dict) -> dict[str, Any]:
    tarea_id, err = _validar_uuid(args.get("tarea_id"), "tarea_id")
    if err:
        return err
    actual = await db.get("tareas", tarea_id)
    if actual is None:
        return _error("no_existe", "Esa tarea ya no está en el hub.")
    ahora = datetime.now(timezone.utc).isoformat()
    fila = await db.update(
        "tareas", tarea_id, {"eliminado_en": ahora}
    )
    if fila is None:
        return _error("interno", "No se pudo mandar la tarea a la papelera.")
    return _ok(
        {
            "id": tarea_id,
            "titulo": actual["titulo"],
            "reversible": True,
            "nota": "Está en la papelera; el usuario puede restaurarla desde la app.",
        }
    )


async def _editar_evento(db: Postgrest, args: dict) -> dict[str, Any]:
    evento_id, err = _validar_uuid(args.get("evento_id"), "evento_id")
    if err:
        return err
    campos = {k: v for k, v in args.items() if k != "evento_id"}
    if not campos:
        return _error(
            "validacion",
            "No me pasaste qué campo cambiar del evento.",
        )
    try:
        body = EventoUpdate(**campos)
    except ValidationError as e:
        return _err_validacion(e)
    payload = body.model_dump(mode="json", exclude_unset=True)
    fila = await db.update("eventos", evento_id, payload)
    if fila is None:
        return _error("no_existe", "Ese evento ya no está en el hub.")
    return _ok(
        {
            "id": evento_id,
            "titulo": fila["titulo"],
            "inicia_en_legible": _resumen_fecha(fila.get("inicia_en")),
        }
    )


async def _eliminar_evento(db: Postgrest, args: dict) -> dict[str, Any]:
    evento_id, err = _validar_uuid(args.get("evento_id"), "evento_id")
    if err:
        return err
    actual = await db.get("eventos", evento_id)
    if actual is None:
        return _error("no_existe", "Ese evento ya no está en el hub.")
    ahora = datetime.now(timezone.utc).isoformat()
    fila = await db.update("eventos", evento_id, {"eliminado_en": ahora})
    if fila is None:
        return _error("interno", "No se pudo mandar el evento a la papelera.")
    return _ok(
        {
            "id": evento_id,
            "titulo": actual["titulo"],
            "reversible": True,
        }
    )


async def _editar_apunte(db: Postgrest, args: dict) -> dict[str, Any]:
    apunte_id, err = _validar_uuid(args.get("apunte_id"), "apunte_id")
    if err:
        return err
    campos = {k: v for k, v in args.items() if k != "apunte_id"}
    if not campos:
        return _error(
            "validacion", "No me pasaste qué campo cambiar del apunte."
        )
    try:
        body = ApunteUpdate(**campos)
    except ValidationError as e:
        return _err_validacion(e)
    payload = body.model_dump(mode="json", exclude_unset=True)
    fila = await db.update("apuntes", apunte_id, payload)
    if fila is None:
        return _error("no_existe", "Ese apunte ya no está en el hub.")
    return _ok(
        {
            "id": apunte_id,
            "titulo": fila["titulo"],
            "etiquetas": fila.get("etiquetas", []),
        }
    )


async def _eliminar_apunte(db: Postgrest, args: dict) -> dict[str, Any]:
    apunte_id, err = _validar_uuid(args.get("apunte_id"), "apunte_id")
    if err:
        return err
    actual = await db.get("apuntes", apunte_id)
    if actual is None:
        return _error("no_existe", "Ese apunte ya no está en el hub.")
    ahora = datetime.now(timezone.utc).isoformat()
    fila = await db.update("apuntes", apunte_id, {"eliminado_en": ahora})
    if fila is None:
        return _error("interno", "No se pudo mandar el apunte a la papelera.")
    return _ok(
        {
            "id": apunte_id,
            "titulo": actual["titulo"],
            "reversible": True,
        }
    )


# ── Proyectos: crear / editar / aparcar / terminar / reactivar ──────

_TOPE_PROYECTOS_ACTIVOS = 3
_MSG_TOPE = (
    f"Ya hay {_TOPE_PROYECTOS_ACTIVOS} proyectos activos. Aparca o "
    "termina uno primero."
)


async def _contar_proyectos_activos(
    db: Postgrest, *, excluir_id: str | None = None
) -> int:
    activos = await db.list("proyectos", filters={"estado": "activo"})
    if excluir_id:
        activos = [p for p in activos if p["id"] != excluir_id]
    return len(activos)


async def _crear_proyecto(db: Postgrest, args: dict) -> dict[str, Any]:
    try:
        body = ProyectoCreate(**args)
    except ValidationError as e:
        return _err_validacion(e)
    payload = body.model_dump(mode="json", exclude_none=True)

    if payload.get("estado", "activo") == "activo":
        if await _contar_proyectos_activos(db) >= _TOPE_PROYECTOS_ACTIVOS:
            return _error(
                "tope_proyectos",
                _MSG_TOPE,
                sugerencia=(
                    "Sugiere al usuario que aparque o termine alguno, "
                    "y vuelve a llamarme. O crea el nuevo como "
                    "`aparcado` para guardarlo sin activarlo."
                ),
            )
    payload["ultima_actividad_en"] = datetime.now(timezone.utc).isoformat()
    fila = await db.insert("proyectos", payload)
    return _ok(
        {
            "id": fila["id"],
            "nombre": fila["nombre"],
            "estado": fila["estado"],
        }
    )


async def _editar_proyecto(db: Postgrest, args: dict) -> dict[str, Any]:
    proyecto_id, err = _validar_uuid(args.get("proyecto_id"), "proyecto_id")
    if err:
        return err
    campos = {k: v for k, v in args.items() if k != "proyecto_id"}
    if not campos:
        return _error("validacion", "No me pasaste qué campo cambiar.")
    # Bloqueamos el cambio de `estado` por esta vía — para eso hay
    # tools dedicadas que enforce-an el tope de 3.
    if "estado" in campos:
        return _error(
            "validacion",
            "Para cambiar el estado del proyecto usa "
            "`aparcar_proyecto`, `terminar_proyecto` o "
            "`reactivar_proyecto`.",
        )
    try:
        body = ProyectoUpdate(**campos)
    except ValidationError as e:
        return _err_validacion(e)
    payload = body.model_dump(mode="json", exclude_unset=True)
    payload["ultima_actividad_en"] = datetime.now(timezone.utc).isoformat()
    fila = await db.update("proyectos", proyecto_id, payload)
    if fila is None:
        return _error("no_existe", "Ese proyecto ya no está en el hub.")
    return _ok(
        {
            "id": proyecto_id,
            "nombre": fila["nombre"],
            "estado": fila["estado"],
        }
    )


async def _cambiar_estado_proyecto(
    db: Postgrest,
    args: dict,
    *,
    nuevo_estado: str,
) -> dict[str, Any]:
    """Lógica compartida entre aparcar / terminar / reactivar."""
    proyecto_id, err = _validar_uuid(args.get("proyecto_id"), "proyecto_id")
    if err:
        return err

    actual = await db.get("proyectos", proyecto_id)
    if actual is None:
        return _error("no_existe", "Ese proyecto ya no está en el hub.")
    estado_actual = actual["estado"]
    if estado_actual == nuevo_estado:
        return _ok(
            {
                "id": proyecto_id,
                "nombre": actual["nombre"],
                "estado": nuevo_estado,
                "ya_estaba_asi": True,
            }
        )

    ahora = datetime.now(timezone.utc).isoformat()
    payload: dict[str, Any] = {
        "estado": nuevo_estado,
        "ultima_actividad_en": ahora,
    }
    if nuevo_estado == "activo":
        # Reactivar: aplicar tope.
        activos = await _contar_proyectos_activos(db, excluir_id=proyecto_id)
        if activos >= _TOPE_PROYECTOS_ACTIVOS:
            return _error(
                "tope_proyectos",
                _MSG_TOPE,
                sugerencia=(
                    "Sugiere al usuario que aparque o termine otro "
                    "antes de reactivar este."
                ),
            )
        payload["inactivo_desde"] = None
    else:
        payload["inactivo_desde"] = ahora

    fila = await db.update("proyectos", proyecto_id, payload)
    if fila is None:
        return _error("interno", "No se pudo cambiar el estado.")
    return _ok(
        {
            "id": proyecto_id,
            "nombre": fila["nombre"],
            "estado": fila["estado"],
            "estado_anterior": estado_actual,
        }
    )


async def _aparcar_proyecto(db: Postgrest, args: dict) -> dict[str, Any]:
    return await _cambiar_estado_proyecto(db, args, nuevo_estado="aparcado")


async def _terminar_proyecto(db: Postgrest, args: dict) -> dict[str, Any]:
    return await _cambiar_estado_proyecto(db, args, nuevo_estado="terminado")


async def _reactivar_proyecto(db: Postgrest, args: dict) -> dict[str, Any]:
    return await _cambiar_estado_proyecto(db, args, nuevo_estado="activo")


# ── buscar_apuntes — RAG, solo lectura (Capa 3 Paso 1) ──────────────


async def _buscar_apuntes(db: Postgrest, args: dict) -> dict[str, Any]:
    consulta = (args.get("consulta") or "").strip()
    if not consulta:
        return _error(
            "validacion",
            "Falta la `consulta` (qué buscar en los apuntes).",
        )
    top_k = args.get("top_k") or 5
    try:
        top_k = max(1, min(10, int(top_k)))
    except (ValueError, TypeError):
        top_k = 5

    filas = await _buscar_apuntes_rag(db, consulta=consulta, top_k=top_k)
    # Recortamos lo que devolvemos al modelo: solo id, título,
    # fragmento y distancia. Sin metadata extra que infle el prompt.
    return _ok(
        {
            "consulta": consulta,
            "resultados": [
                {
                    "apunte_id": r["apunte_id"],
                    "titulo": r["titulo"],
                    "fragmento": r["fragmento"],
                    "distancia": round(float(r["distancia"]), 4),
                }
                for r in filas
            ],
            # Hint para el modelo: si el mejor match tiene distancia
            # alta (>1.0), probablemente no hay un apunte relevante.
            "nota": (
                "Si todos los resultados tienen distancia > 1.0, "
                "el match es débil — dile al usuario que no "
                "encontraste nada claro en lugar de inventar."
            ),
        }
    )


# ── buscar_material — biblioteca de aprendizaje, solo lectura (Fase 1) ──


async def _buscar_material(db: Postgrest, args: dict) -> dict[str, Any]:
    consulta = (args.get("consulta") or "").strip()
    if not consulta:
        return _error(
            "validacion",
            "Falta la `consulta` (qué buscar en el material).",
        )
    skill = (args.get("skill") or "").strip() or None
    bloque = (args.get("bloque") or "").strip() or None
    top_k = args.get("top_k") or 5
    try:
        top_k = max(1, min(10, int(top_k)))
    except (ValueError, TypeError):
        top_k = 5

    filas = await _buscar_material_rag(
        db, consulta=consulta, skill=skill, bloque=bloque, top_k=top_k
    )
    return _ok(
        {
            "consulta": consulta,
            "skill": skill,
            "bloque": bloque,
            "resultados": [
                {
                    "skill": r["skill"],
                    "bloque": r["bloque"],
                    "fuente": r.get("fuente"),
                    "fragmento": r["fragmento"],
                    "distancia": round(float(r["distancia"]), 4),
                }
                for r in filas
            ],
            "nota": (
                "Si todos los resultados tienen distancia > 1.0, el "
                "match es débil — dile al usuario que no encontraste "
                "material claro en lugar de inventar."
            ),
        }
    )


# ── leer_apunte — solo lectura, contenido completo (Capa 3 Paso 2) ──


async def _leer_apunte(db: Postgrest, args: dict) -> dict[str, Any]:
    """Devuelve el apunte completo (título + contenido + etiquetas)
    para que el modelo lo use al resumir, generar preguntas o
    explicar. Filtra papelera: si el apunte está soft-deleted, lo
    tratamos como inexistente — Matix nunca debe usar contenido
    borrado por el usuario.
    """
    raw_id = args.get("apunte_id")
    apunte_id, err = _validar_uuid(raw_id, "apunte_id")
    if err:
        return err

    apunte = await db.get("apuntes", apunte_id)
    if apunte is None:
        return _error(
            "no_existe",
            "Ese apunte no está en el hub.",
            sugerencia=(
                "Si llegaste a este id desde `buscar_apuntes`, "
                "puede que mientras tanto se haya borrado. Vuelve "
                "a buscar."
            ),
        )
    if apunte.get("eliminado_en"):
        return _error(
            "en_papelera",
            "Ese apunte está en la papelera del usuario.",
            sugerencia=(
                "No leas su contenido. Si Gian Piero lo quiere, "
                "tiene que restaurarlo desde la app."
            ),
        )

    return _ok(
        {
            "id": apunte_id,
            "titulo": apunte.get("titulo", ""),
            "contenido": apunte.get("contenido", ""),
            "etiquetas": apunte.get("etiquetas") or [],
            "curso_id": apunte.get("curso_id"),
            "proyecto_id": apunte.get("proyecto_id"),
        }
    )


# ── consultar_uso — solo lectura ─────────────────────────────────────


async def _consultar_uso(_db: Postgrest, _args: dict) -> dict[str, Any]:
    """Devuelve el snapshot del medidor. Sin efectos en BD."""
    s = medidor.snapshot()
    # Resumimos para el modelo — el dict completo es ruido si solo
    # quiere narrar "gastaste $X y mandaste N llamadas".
    return _ok(
        {
            "costo_usd": s["costo_usd"],
            "total_tokens": s["total_tokens"],
            "prompt_tokens": s["prompt_tokens"],
            "cached_prompt_tokens": s["cached_prompt_tokens"],
            "completion_tokens": s["completion_tokens"],
            "llamadas_chat": s["llamadas_chat"],
            "segundos_whisper": s["segundos_whisper"],
            "llamadas_whisper": s["llamadas_whisper"],
        }
    )


# ── Repetición (copia de la lógica del router de tareas) ─────────────


def _avanzar_fecha(iso: str, repeticion: str) -> str:
    dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    if repeticion == "diaria":
        nuevo = dt + timedelta(days=1)
    elif repeticion == "semanal":
        nuevo = dt + timedelta(weeks=1)
    elif repeticion == "mensual":
        nuevo = dt + timedelta(days=30)
    elif repeticion == "anual":
        nuevo = dt + timedelta(days=365)
    else:
        nuevo = dt
    return nuevo.isoformat()


async def _crear_siguiente_instancia(
    db: Postgrest, original: dict, repeticion: str
) -> None:
    nueva: dict = {
        "titulo": original["titulo"],
        "prioridad": original["prioridad"],
        "repeticion": repeticion,
        "vence_en": _avanzar_fecha(original["vence_en"], repeticion),
    }
    for campo in ("nota", "categoria_id", "curso_id", "proyecto_id"):
        if original.get(campo) is not None:
            nueva[campo] = original[campo]
    if original.get("recordar_en"):
        nueva["recordar_en"] = _avanzar_fecha(
            original["recordar_en"], repeticion
        )
    await db.insert("tareas", nueva)


# ─────────────────────────────────────────────────────────────────────
# Dispatcher público
# ─────────────────────────────────────────────────────────────────────


# ─────────────────────────────────────────────────────────────────────
# Consultas del hub (solo lectura) — "pregúntale a tu hub"
#
# El filtrado vive en funciones puras (testeables sin BD): los handlers
# solo traen las filas con `db.list` y delegan el filtro. Los rangos de
# fecha se comparan en fecha local de Lima.
# ─────────────────────────────────────────────────────────────────────


def _fecha_lima(iso: Any) -> date | None:
    """Fecha local (Lima) de un timestamp ISO, o None si no parsea."""
    if not isinstance(iso, str) or not iso:
        return None
    try:
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        return dt.astimezone(timezone(timedelta(hours=-5))).date()
    except Exception:
        return None


def _parse_dia(s: Any) -> date | None:
    """Parsea 'YYYY-MM-DD' (o ISO) a date, o None."""
    if not isinstance(s, str) or not s.strip():
        return None
    try:
        return date.fromisoformat(s.strip()[:10])
    except Exception:
        return None


def filtrar_tareas(
    tareas: list[dict],
    *,
    proyecto_id: str | None = None,
    curso_id: str | None = None,
    estado: str = "pendiente",
    vence_desde: date | None = None,
    vence_hasta: date | None = None,
) -> list[dict]:
    """Filtra tareas (excluye papelera) por proyecto, curso, estado y
    rango de vencimiento. Si hay rango, las tareas sin fecha no entran.
    Ordena por vencimiento ascendente (sin fecha al final)."""
    out: list[dict] = []
    for t in tareas:
        if t.get("eliminado_en"):
            continue
        comp = bool(t.get("completada"))
        if estado == "pendiente" and comp:
            continue
        if estado == "completada" and not comp:
            continue
        if proyecto_id and t.get("proyecto_id") != proyecto_id:
            continue
        if curso_id and t.get("curso_id") != curso_id:
            continue
        if vence_desde or vence_hasta:
            f = _fecha_lima(t.get("vence_en"))
            if f is None:
                continue
            if vence_desde and f < vence_desde:
                continue
            if vence_hasta and f > vence_hasta:
                continue
        out.append(t)
    out.sort(
        key=lambda t: (
            _fecha_lima(t.get("vence_en")) is None,
            _fecha_lima(t.get("vence_en")) or date.max,
        )
    )
    return out


def eventos_en_rango(
    eventos: list[dict], desde: date, hasta: date
) -> list[dict]:
    """Eventos (sin papelera) en [desde, hasta]. Los recurrentes se
    incluyen si ya arrancaron (su ancla cae en o antes de `hasta`),
    marcados con `_recurrente` para que el modelo avise que se repiten."""
    out: list[dict] = []
    for e in eventos:
        if e.get("eliminado_en"):
            continue
        f = _fecha_lima(e.get("inicia_en"))
        if f is None:
            continue
        recurrente = bool(e.get("recurrencia_freq"))
        if recurrente and f <= hasta:
            # Recurrente que ya arrancó: el modelo avisa que se repite.
            out.append({**e, "_recurrente": True})
        elif not recurrente and desde <= f <= hasta:
            out.append(e)
    out.sort(key=lambda e: e.get("inicia_en") or "")
    return out


def _dias_inactivo(proyecto: dict, ahora: datetime) -> int | None:
    ult = proyecto.get("ultima_actividad_en")
    if not isinstance(ult, str) or not ult:
        return None
    try:
        dt = datetime.fromisoformat(ult.replace("Z", "+00:00"))
        return (ahora - dt).days
    except Exception:
        return None


def filtrar_proyectos(
    proyectos: list[dict],
    *,
    estado: str = "activo",
    en_riesgo: bool = False,
    ahora: datetime,
) -> list[dict]:
    """Filtra proyectos por estado y, opcionalmente, solo los activos en
    riesgo (3+ días sin actividad). Anota `dias_inactivo` y `en_riesgo`."""
    out: list[dict] = []
    for p in proyectos:
        est = p.get("estado")
        dias = _dias_inactivo(p, ahora)
        riesgo = est == "activo" and dias is not None and dias >= 3
        if en_riesgo:
            if not riesgo:
                continue
        elif estado != "todos" and est != estado:
            continue
        out.append({**p, "dias_inactivo": dias, "en_riesgo": riesgo})
    return out


async def _consultar_tareas(db: Postgrest, args: dict) -> dict[str, Any]:
    estado = args.get("estado") or "pendiente"
    if estado not in ("pendiente", "completada", "todas"):
        estado = "pendiente"
    tareas = await db.list("tareas", raw_filters={"eliminado_en": "is.null"})
    filtradas = filtrar_tareas(
        tareas,
        proyecto_id=(args.get("proyecto_id") or None),
        curso_id=(args.get("curso_id") or None),
        estado=estado,
        vence_desde=_parse_dia(args.get("vence_desde")),
        vence_hasta=_parse_dia(args.get("vence_hasta")),
    )
    proyectos = await db.list("proyectos")
    cursos = await db.list("cursos")
    nom_proy = {p["id"]: p["nombre"] for p in proyectos}
    nom_curso = {c["id"]: c["nombre"] for c in cursos}
    total = len(filtradas)
    return _ok(
        {
            "total": total,
            "estado": estado,
            "tareas": [
                {
                    "id": t["id"],
                    "titulo": t.get("titulo"),
                    "completada": bool(t.get("completada")),
                    "vence_en": t.get("vence_en"),
                    "prioridad": t.get("prioridad"),
                    "proyecto": nom_proy.get(t.get("proyecto_id")),
                    "curso": nom_curso.get(t.get("curso_id")),
                }
                for t in filtradas[:40]
            ],
            "truncado": total > 40,
        }
    )


async def _consultar_eventos(db: Postgrest, args: dict) -> dict[str, Any]:
    desde = _parse_dia(args.get("desde"))
    hasta = _parse_dia(args.get("hasta"))
    if desde is None or hasta is None:
        return _error(
            "validacion",
            "Faltan `desde` / `hasta` en formato YYYY-MM-DD.",
        )
    if hasta < desde:
        desde, hasta = hasta, desde
    eventos = await db.list("eventos", raw_filters={"eliminado_en": "is.null"})
    enrango = eventos_en_rango(eventos, desde, hasta)
    return _ok(
        {
            "desde": desde.isoformat(),
            "hasta": hasta.isoformat(),
            "total": len(enrango),
            "eventos": [
                {
                    "id": e["id"],
                    "titulo": e.get("titulo"),
                    "inicia_en": e.get("inicia_en"),
                    "termina_en": e.get("termina_en"),
                    "todo_el_dia": bool(e.get("todo_el_dia")),
                    "se_repite": bool(e.get("_recurrente")),
                }
                for e in enrango[:40]
            ],
        }
    )


async def _consultar_proyectos(db: Postgrest, args: dict) -> dict[str, Any]:
    estado = args.get("estado") or "activo"
    if estado not in ("activo", "aparcado", "terminado", "todos"):
        estado = "activo"
    en_riesgo = bool(args.get("en_riesgo"))
    proyectos = await db.list("proyectos")
    ahora = datetime.now(timezone.utc)
    filtrados = filtrar_proyectos(
        proyectos, estado=estado, en_riesgo=en_riesgo, ahora=ahora
    )
    filtrados.sort(key=lambda p: p.get("prioridad") or 99)
    return _ok(
        {
            "total": len(filtrados),
            "en_riesgo_solicitado": en_riesgo,
            "proyectos": [
                {
                    "id": p["id"],
                    "nombre": p.get("nombre"),
                    "estado": p.get("estado"),
                    "prioridad": p.get("prioridad"),
                    "linea_meta": p.get("linea_meta"),
                    "dias_inactivo": p.get("dias_inactivo"),
                    "en_riesgo": p.get("en_riesgo"),
                }
                for p in filtrados
            ],
        }
    )


# ── Apuntes: listado plano sin RAG ──────────────────────────────────


async def _consultar_apuntes(db: Postgrest, args: dict) -> dict[str, Any]:
    """Lista los apuntes vivos por título, sin búsqueda semántica. Para
    que el modelo pueda enumerar y obtener `apunte_id` (editar/borrar por
    nombre) aunque el RAG no esté disponible."""
    texto = (args.get("texto") or "").strip().lower()
    filas = await db.list(
        "apuntes", raw_filters={"eliminado_en": "is.null"}
    )
    if texto:
        filas = [f for f in filas if texto in (f.get("titulo") or "").lower()]
    # Más recientes primero (por actualizado_en si está, si no creado_en).
    filas.sort(
        key=lambda f: f.get("actualizado_en") or f.get("creado_en") or "",
        reverse=True,
    )
    total = len(filas)
    return _ok(
        {
            "total": total,
            "apuntes": [
                {
                    "apunte_id": f["id"],
                    "titulo": f.get("titulo"),
                    "fragmento": ((f.get("contenido") or "")[:120]).strip(),
                }
                for f in filas[:40]
            ],
            "truncado": total > 40,
        }
    )


# ── Finanzas: movimientos (crear / consultar / editar / eliminar) ────


async def _crear_movimiento(db: Postgrest, args: dict) -> dict[str, Any]:
    # `senal` (lo que se vio en la imagen) NO es columna: se usa solo para
    # verificar el tipo, luego se descarta.
    senal = args.pop("senal", None) if isinstance(args, dict) else None
    try:
        body = MovimientoCreate(**args)
    except ValidationError as e:
        return _err_validacion(e)
    payload = body.model_dump(mode="json", exclude_none=True)
    # Reconcilia el tipo con la señal observada (el signo/keyword manda).
    inferido = finanzas.inferir_tipo(senal)
    if inferido and inferido != payload["tipo"]:
        payload["tipo"] = inferido
    # Un movimiento suelto también lleva su lote_id propio, para que
    # `revertir_ultimo_lote` pueda deshacerlo si fue lo último que hice.
    payload["lote_id"] = str(uuid.uuid4())
    fila = await db.insert("movimientos", payload)
    return _ok(
        {
            "id": fila["id"],
            "tipo": fila["tipo"],
            "monto": fila["monto"],
            "categoria": fila.get("categoria"),
            "fecha": fila.get("fecha"),
        }
    )


async def _consultar_movimientos(db: Postgrest, args: dict) -> dict[str, Any]:
    tipo = args.get("tipo") or "todos"
    if tipo not in ("ingreso", "gasto", "todos"):
        tipo = "todos"
    filas = await db.list("movimientos", order="fecha.desc")
    if tipo != "todos":
        filas = [m for m in filas if m.get("tipo") == tipo]
    ingresos = sum(
        float(m["monto"]) for m in filas if m.get("tipo") == "ingreso"
    )
    gastos = sum(
        float(m["monto"]) for m in filas if m.get("tipo") == "gasto"
    )
    total = len(filas)
    return _ok(
        {
            "total": total,
            "ingresos": round(ingresos, 2),
            "gastos": round(gastos, 2),
            "balance": round(ingresos - gastos, 2),
            "movimientos": [
                {
                    "id": m["id"],
                    "tipo": m.get("tipo"),
                    "monto": m.get("monto"),
                    "categoria": m.get("categoria"),
                    "fecha": m.get("fecha"),
                    "nota": m.get("nota"),
                }
                for m in filas[:40]
            ],
            "truncado": total > 40,
        }
    )


async def _editar_movimiento(db: Postgrest, args: dict) -> dict[str, Any]:
    movimiento_id, err = _validar_uuid(args.get("movimiento_id"), "movimiento_id")
    if err:
        return err
    campos = {k: v for k, v in args.items() if k != "movimiento_id"}
    if not campos:
        return _error(
            "validacion", "No me pasaste qué campo cambiar del movimiento."
        )
    try:
        body = MovimientoUpdate(**campos)
    except ValidationError as e:
        return _err_validacion(e)
    payload = body.model_dump(mode="json", exclude_unset=True)
    fila = await db.update("movimientos", movimiento_id, payload)
    if fila is None:
        return _error("no_existe", "Ese movimiento ya no está en el hub.")
    return _ok(
        {
            "id": movimiento_id,
            "tipo": fila.get("tipo"),
            "monto": fila.get("monto"),
            "categoria": fila.get("categoria"),
        }
    )


async def _eliminar_movimiento(db: Postgrest, args: dict) -> dict[str, Any]:
    movimiento_id, err = _validar_uuid(args.get("movimiento_id"), "movimiento_id")
    if err:
        return err
    actual = await db.get("movimientos", movimiento_id)
    if actual is None:
        return _error("no_existe", "Ese movimiento ya no está en el hub.")
    ok = await db.delete("movimientos", movimiento_id)
    if not ok:
        return _error("interno", "No se pudo borrar el movimiento.")
    return _ok(
        {
            "id": movimiento_id,
            "tipo": actual.get("tipo"),
            "monto": actual.get("monto"),
            # Finanzas no tiene papelera: el borrado es permanente.
            "reversible": False,
        }
    )


# Tope del lote: leer una captura no debería meter cientos de filas de golpe.
_MAX_LOTE_MOVIMIENTOS = 50


async def _registrar_movimientos(db: Postgrest, args: dict) -> dict[str, Any]:
    """Registra un LOTE de movimientos (de una imagen) en dos pasos seguros:
    preview (no escribe) → confirmado (escribe con un `lote_id` compartido).
    Reconcilia el tipo con la `senal` vista y respeta el `filtro` del usuario
    («solo los gastos» descarta los ingresos)."""
    items = args.get("movimientos")
    if not isinstance(items, list) or not items:
        return _error(
            "validacion", "Pásame `movimientos`: una lista con al menos uno."
        )
    if len(items) > _MAX_LOTE_MOVIMIENTOS:
        return _error(
            "validacion",
            f"Son {len(items)} movimientos de una — demasiados. Pártelo "
            f"(máx {_MAX_LOTE_MOVIMIENTOS} por lote).",
        )
    filtro = args.get("filtro") or "todos"
    if filtro not in ("todos", "solo_gastos", "solo_ingresos"):
        filtro = "todos"
    confirmado = bool(args.get("confirmado"))

    # 1) Validar + clasificar TODOS primero (sin escribir nada).
    validados: list[dict[str, Any]] = []
    descartados_por_filtro = 0
    correcciones_por_senal = 0
    for i, item in enumerate(items):
        if not isinstance(item, dict):
            return _error(
                "validacion", f"El movimiento #{i + 1} no es un objeto válido."
            )
        it = dict(item)
        senal = it.pop("senal", None)
        try:
            body = MovimientoCreate(**it)
        except ValidationError as e:
            val = _err_validacion(e)
            val["mensaje"] = f"Movimiento #{i + 1}: {val['mensaje']}"
            return val
        payload = body.model_dump(mode="json", exclude_none=True)
        # La señal observada (signo/keyword) manda sobre el `tipo` propuesto:
        # así un ingreso no termina anotado como gasto.
        inferido = finanzas.inferir_tipo(senal)
        if inferido and inferido != payload["tipo"]:
            payload["tipo"] = inferido
            correcciones_por_senal += 1
        # Filtro del usuario: «solo gastos» / «solo ingresos» descarta el resto.
        if filtro == "solo_gastos" and payload["tipo"] != "gasto":
            descartados_por_filtro += 1
            continue
        if filtro == "solo_ingresos" and payload["tipo"] != "ingreso":
            descartados_por_filtro += 1
            continue
        validados.append(payload)

    if not validados:
        return _error(
            "validacion",
            "Con ese filtro no queda ningún movimiento para registrar.",
        )

    total_gastos = round(
        sum(m["monto"] for m in validados if m["tipo"] == "gasto"), 2
    )
    total_ingresos = round(
        sum(m["monto"] for m in validados if m["tipo"] == "ingreso"), 2
    )
    resumen = [
        {
            "tipo": m["tipo"],
            "monto": m["monto"],
            "categoria": m.get("categoria"),
            "fecha": m.get("fecha"),
        }
        for m in validados
    ]

    # 2) PREVIEW: sin confirmar, no escribe. Matix muestra la lista y pregunta.
    if not confirmado:
        return _ok(
            {
                "preview": True,
                "n": len(validados),
                "movimientos": resumen,
                "total_gastos": total_gastos,
                "total_ingresos": total_ingresos,
                "descartados_por_filtro": descartados_por_filtro,
                "correcciones_por_senal": correcciones_por_senal,
                "nota": (
                    "NO registré nada todavía. Muéstrale esta lista al usuario y "
                    "pídele que confirme; recién ahí llámame con confirmado=true."
                ),
            }
        )

    # 3) CONFIRMADO: inserta el lote completo con un lote_id compartido.
    lote_id = str(uuid.uuid4())
    creados: list[dict[str, Any]] = []
    for payload in validados:
        payload["lote_id"] = lote_id
        fila = await db.insert("movimientos", payload)
        creados.append(
            {
                "id": fila["id"],
                "tipo": fila["tipo"],
                "monto": fila["monto"],
                "categoria": fila.get("categoria"),
            }
        )
    return _ok(
        {
            "registrado": True,
            "lote_id": lote_id,
            "total": len(creados),
            "total_gastos": total_gastos,
            "total_ingresos": total_ingresos,
            "descartados_por_filtro": descartados_por_filtro,
            "movimientos": creados,
        }
    )


async def _revertir_ultimo_lote(db: Postgrest, args: dict) -> dict[str, Any]:
    """Deshace SOLO el último lote que registró Matix (por lote_id). Nunca
    toca movimientos sin lote (creados a mano) ni lotes anteriores. Dos pasos:
    preview → confirmado."""
    confirmado = bool(args.get("confirmado"))
    # El último lote = el lote_id del movimiento con lote_id más reciente.
    recientes = await db.list(
        "movimientos",
        raw_filters={"lote_id": "not.is.null"},
        order="creado_en.desc",
        limit=1,
    )
    if not recientes:
        return _error(
            "no_existe",
            "No hay ningún movimiento registrado por mí que pueda revertir.",
        )
    lote_id = recientes[0]["lote_id"]
    del_lote = await db.list("movimientos", filters={"lote_id": lote_id})
    resumen = [
        {
            "id": m["id"],
            "tipo": m.get("tipo"),
            "monto": m.get("monto"),
            "categoria": m.get("categoria"),
            "fecha": m.get("fecha"),
        }
        for m in del_lote
    ]

    if not confirmado:
        return _ok(
            {
                "preview": True,
                "lote_id": lote_id,
                "n": len(del_lote),
                "movimientos": resumen,
                "nota": (
                    "Esto borraría SOLO estos (el último lote). No toco nada más. "
                    "Pide confirmación; recién ahí llámame con confirmado=true."
                ),
            }
        )

    borrados = await db.delete_where("movimientos", filters={"lote_id": lote_id})
    return _ok(
        {
            "revertido": True,
            "lote_id": lote_id,
            "borrados": borrados,
            "movimientos": resumen,
            "reversible": False,
        }
    )


# ── Navegación: abrir una sección de la app ─────────────────────────

_SECCIONES_NAVEGABLES = {
    "inicio",
    "tareas",
    "calendario",
    "proyectos",
    "universidad",
    "finanzas",
    "apuntes",
    "ajustes",
}


async def _navegar(_db: Postgrest, args: dict) -> dict[str, Any]:
    """No toca datos: devuelve la sección a abrir. El chat la propaga a
    la app, que cambia de pestaña o empuja la pantalla correspondiente."""
    seccion = (args.get("seccion") or "").strip().lower()
    if seccion not in _SECCIONES_NAVEGABLES:
        return _error(
            "validacion",
            f"No conozco una sección «{seccion}». Las válidas son: "
            + ", ".join(sorted(_SECCIONES_NAVEGABLES))
            + ".",
        )
    return _ok({"seccion": seccion})


_TIPOS_OPCIONES = {"seleccion_unica", "seleccion_multiple", "texto"}


async def _preguntar_con_opciones(_db: Postgrest, args: dict) -> dict[str, Any]:
    """No toca datos: arma el bloque interactivo (pregunta + opciones + tipo).
    El chat lo propaga a la app, que pinta las opciones tocables y termina el
    turno; el usuario responde tocando."""
    pregunta = (args.get("pregunta") or "").strip()
    if not pregunta:
        return _error("validacion", "Falta la `pregunta`.")
    tipo = (args.get("tipo") or "").strip().lower()
    if tipo not in _TIPOS_OPCIONES:
        return _error(
            "validacion",
            "tipo inválido. Usa seleccion_unica, seleccion_multiple o texto.",
        )
    opciones = [
        str(o).strip()
        for o in (args.get("opciones") or [])
        if str(o).strip()
    ][:6]  # tope de 6: un set chico y claro, no un menú infinito
    if tipo != "texto" and len(opciones) < 2:
        return _error(
            "validacion",
            "Para seleccion_unica/multiple pasa al menos 2 opciones.",
        )
    return _ok({"pregunta": pregunta, "opciones": opciones, "tipo": tipo})


# ── Modos de Matix: activar / desactivar ────────────────────────────


async def _activar_modo(db: Postgrest, args: dict) -> dict[str, Any]:
    modo = (args.get("modo") or "").strip().lower()
    if not modos.existe_modo(modo):
        disp = ", ".join(m["nombre"] for m in modos.listar_modos()) or "(ninguno)"
        return _error(
            "validacion",
            f"No conozco el modo «{modo}». Los modos son: {disp}.",
        )
    await modos.set_modo_activo(db, modo)
    meta = modos.meta_modo(modo) or {}
    return _ok({"modo": modo, "etiqueta": meta.get("etiqueta", modo)})


async def _desactivar_modo(db: Postgrest, _args: dict) -> dict[str, Any]:
    await modos.set_modo_activo(db, None)
    return _ok({"modo": None})


# ── Memoria personal: recordar / actualizar / olvidar / buscar ──────


async def _recordar(db: Postgrest, args: dict) -> dict[str, Any]:
    contenido = (args.get("contenido") or "").strip()
    if not contenido:
        return _error("validacion", "No me dijiste qué recordar.")
    esencial = args.get("esencial")
    fila = await memoria.recordar(
        db,
        contenido=contenido,
        categoria=args.get("categoria"),
        esencial=True if esencial is None else bool(esencial),
    )
    return _ok(
        {
            "id": fila["id"],
            "contenido": fila["contenido"],
            "categoria": fila.get("categoria"),
        }
    )


async def _actualizar_memoria(db: Postgrest, args: dict) -> dict[str, Any]:
    memoria_id, err = _validar_uuid(args.get("memoria_id"), "memoria_id")
    if err:
        return err
    campos = {k: v for k, v in args.items() if k != "memoria_id"}
    if not campos:
        return _error("validacion", "No me pasaste qué cambiar del recuerdo.")
    fila = await memoria.actualizar(
        db,
        memoria_id=memoria_id,
        contenido=campos.get("contenido"),
        categoria=campos.get("categoria"),
        esencial=campos.get("esencial"),
    )
    if fila is None:
        return _error("no_existe", "Ese recuerdo ya no está en la memoria.")
    return _ok({"id": memoria_id, "contenido": fila.get("contenido")})


async def _olvidar(db: Postgrest, args: dict) -> dict[str, Any]:
    memoria_id, err = _validar_uuid(args.get("memoria_id"), "memoria_id")
    if err:
        return err
    actual = await db.get("memoria", memoria_id)
    if actual is None:
        return _error("no_existe", "Ese recuerdo ya no está en la memoria.")
    ok = await memoria.olvidar(db, memoria_id=memoria_id)
    if not ok:
        return _error("interno", "No se pudo borrar el recuerdo.")
    return _ok(
        {"id": memoria_id, "contenido": actual.get("contenido"), "reversible": False}
    )


async def _buscar_memoria(db: Postgrest, args: dict) -> dict[str, Any]:
    consulta = (args.get("consulta") or "").strip()
    if not consulta:
        return _error("validacion", "Falta la `consulta` (qué buscar).")
    filas = await memoria.buscar(db, consulta=consulta, top_k=5)
    return _ok(
        {
            "consulta": consulta,
            "resultados": [
                {
                    "memoria_id": r["id"],
                    "contenido": r["contenido"],
                    "categoria": r.get("categoria"),
                    "distancia": round(float(r["distancia"]), 4),
                }
                for r in filas
            ],
            "nota": (
                "Si todo viene con distancia > 1.0, el match es débil — dilo "
                "en vez de inventar."
            ),
        }
    )


# Mapa de nombre → handler. Mantener sincronizado con TOOL_DEFINITIONS.
_HANDLERS = {
    # Crear
    "crear_tarea": _crear_tarea,
    "crear_tareas": _crear_tareas,
    "crear_evento": _crear_evento,
    "crear_apunte": _crear_apunte,
    "crear_proyecto": _crear_proyecto,
    # Editar
    "editar_tarea": _editar_tarea,
    "editar_evento": _editar_evento,
    "editar_apunte": _editar_apunte,
    "editar_proyecto": _editar_proyecto,
    # Completar / reabrir tareas
    "completar_tarea": _completar_tarea,
    "reabrir_tarea": _reabrir_tarea,
    # Eliminar (papelera, soft delete)
    "eliminar_tarea": _eliminar_tarea,
    "eliminar_evento": _eliminar_evento,
    "eliminar_apunte": _eliminar_apunte,
    # Proyectos: cambios de estado con tope de 3
    "aparcar_proyecto": _aparcar_proyecto,
    "terminar_proyecto": _terminar_proyecto,
    "reactivar_proyecto": _reactivar_proyecto,
    # Acción siguiente + cierre
    "marcar_accion_siguiente_hecha": _marcar_accion_siguiente_hecha,
    "registrar_cierre": _registrar_cierre,
    # Finanzas (movimientos)
    "crear_movimiento": _crear_movimiento,
    "registrar_movimientos": _registrar_movimientos,
    "revertir_ultimo_lote": _revertir_ultimo_lote,
    "editar_movimiento": _editar_movimiento,
    "eliminar_movimiento": _eliminar_movimiento,
    # Navegación (no toca datos)
    "navegar": _navegar,
    "preguntar_con_opciones": _preguntar_con_opciones,
    # Modos de Matix
    "activar_modo": _activar_modo,
    "desactivar_modo": _desactivar_modo,
    # Memoria personal
    "recordar": _recordar,
    "actualizar_memoria": _actualizar_memoria,
    "olvidar": _olvidar,
    # Solo lectura
    "buscar_memoria": _buscar_memoria,
    "consultar_apuntes": _consultar_apuntes,
    "consultar_movimientos": _consultar_movimientos,
    "buscar_apuntes": _buscar_apuntes,
    "buscar_material": _buscar_material,
    "leer_apunte": _leer_apunte,
    "consultar_uso": _consultar_uso,
    "consultar_tareas": _consultar_tareas,
    "consultar_eventos": _consultar_eventos,
    "consultar_proyectos": _consultar_proyectos,
}


# Mapa de nombre → tablas afectadas. El chat lo expone para que la
# app Flutter sepa qué providers invalidar.
TABLAS_AFECTADAS = {
    "crear_tarea": ["tareas"],
    "crear_tareas": ["tareas"],
    "crear_evento": ["eventos"],
    "crear_apunte": ["apuntes"],
    "crear_proyecto": ["proyectos"],
    "editar_tarea": ["tareas"],
    "editar_evento": ["eventos"],
    "editar_apunte": ["apuntes"],
    "editar_proyecto": ["proyectos"],
    "completar_tarea": ["tareas"],
    "reabrir_tarea": ["tareas"],
    "eliminar_tarea": ["tareas"],
    "eliminar_evento": ["eventos"],
    "eliminar_apunte": ["apuntes"],
    "aparcar_proyecto": ["proyectos"],
    "terminar_proyecto": ["proyectos"],
    "reactivar_proyecto": ["proyectos"],
    "marcar_accion_siguiente_hecha": ["tareas", "proyectos"],
    "registrar_cierre": ["cierres_dia"],
    # Finanzas
    "crear_movimiento": ["movimientos"],
    "registrar_movimientos": ["movimientos"],
    "revertir_ultimo_lote": ["movimientos"],
    "editar_movimiento": ["movimientos"],
    "eliminar_movimiento": ["movimientos"],
    # Navegación (no cambia datos)
    "navegar": [],
    "preguntar_con_opciones": [],
    # Modos (el modo activo se surfacea aparte en la respuesta del chat)
    "activar_modo": [],
    "desactivar_modo": [],
    # Memoria personal (la pantalla "Sobre mí" se refresca al cambiar)
    "recordar": ["memoria"],
    "actualizar_memoria": ["memoria"],
    "olvidar": ["memoria"],
    "buscar_memoria": [],  # solo lectura
    "consultar_apuntes": [],  # solo lectura
    "consultar_movimientos": [],  # solo lectura
    "buscar_apuntes": [],  # solo lectura
    "buscar_material": [],  # solo lectura
    "leer_apunte": [],  # solo lectura
    "consultar_uso": [],  # solo lectura
    "consultar_tareas": [],  # solo lectura
    "consultar_eventos": [],  # solo lectura
    "consultar_proyectos": [],  # solo lectura
}


async def ejecutar_tool(
    db: Postgrest, name: str, args: dict[str, Any]
) -> dict[str, Any]:
    """Ejecuta una tool por nombre. Atrapa todas las excepciones para
    que el modelo siempre reciba un payload estructurado, nunca un
    crash. El caller (chat.py) decide si reintentar o devolver al
    usuario."""
    handler = _HANDLERS.get(name)
    if handler is None:
        return _error(
            "desconocida",
            f"No tengo una herramienta llamada «{name}».",
        )
    try:
        return await handler(db, args)
    except httpx.HTTPStatusError as e:
        # Falla de una operación contra la BD (PostgREST). El cliente solo
        # veía "HTTPStatusError" opaco; logueamos el status + cuerpo REAL
        # (ej. PGRST205 "Could not find the table …" cuando falta una
        # migración) para poder diagnosticarlo en los logs de Railway, y
        # surfaceamos el código HTTP al modelo/usuario.
        cuerpo = ""
        try:
            cuerpo = e.response.text[:500]
        except Exception:  # noqa: BLE001
            pass
        logger.error(
            "tool «%s» falló: HTTP %s -> %s",
            name,
            e.response.status_code,
            cuerpo,
        )
        return _error(
            "interno",
            f"Algo falló al ejecutar «{name}» (HTTP {e.response.status_code}).",
            sugerencia=(
                "Probablemente falta aplicar una migración en la BD o la "
                "tabla no existe. Revisa los logs del cerebro."
            ),
        )
    except Exception as e:  # noqa: BLE001
        # Nunca propagar — un crash de la tool dejaría al modelo sin
        # contexto. Logueamos el traceback completo (Railway) y devolvemos
        # algo que el modelo pueda explicar.
        logger.exception("tool «%s» falló", name)
        return _error(
            "interno",
            f"Algo falló al ejecutar «{name}» ({type(e).__name__}).",
            sugerencia=(
                "Dile al usuario que algo se rompió en el cerebro "
                "y que reintente en un momento."
            ),
        )
