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

from datetime import date, datetime, timedelta, timezone
from typing import Any
from uuid import UUID

from pydantic import ValidationError

from ..db import Postgrest
from ..schemas.apuntes import ApunteCreate, ApunteUpdate
from ..schemas.cierres_dia import CierreDiaCreate
from ..schemas.eventos import EventoCreate, EventoUpdate
from ..schemas.proyectos import ProyectoCreate, ProyectoUpdate
from ..schemas.tareas import TareaCreate, TareaUpdate
from .indexador import buscar_apuntes as _buscar_apuntes_rag
from .uso import medidor

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


TOOL_DEFINITIONS: list[dict[str, Any]] = [
    {
        "type": "function",
        "function": {
            "name": "crear_tarea",
            "description": (
                "Crea una tarea en el hub. Úsala cuando el usuario "
                "pida 'agendá', 'apuntá', 'agregá una tarea' o "
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
                "Crea un apunte (nota). Úsalo cuando el usuario "
                "pida 'apuntá', 'anotá esto', 'guardame esto'. "
                "El contenido puede tener saltos de línea."
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
                "`completar_tarea`. Usalo cuando el usuario diga "
                "«reabrí», «deshacé», «marcá X como pendiente otra "
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
                "de X» o equivalente, marcá esa tarea como completada "
                "y limpiá la acción siguiente del proyecto (queda "
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
                "Si la fecha ya tiene cierre, se actualiza. Pasale "
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
                "Edita campos de una tarea existente. Pasale el "
                "`tarea_id` y SOLO los campos que querés cambiar. Si "
                "el usuario pide reagendar, cambiar prioridad, mover "
                "a otro proyecto/curso, agregar o quitar una nota — "
                "es esta. Para completar/reabrir tenés tools "
                "dedicadas; no las uses acá."
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
                "diga «borrá esa tarea», «sacala», «eliminala». "
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
                "Edita campos de un evento existente. Pasale el "
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
                "Edita un apunte existente. Pasale el `apunte_id` y "
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
                "mensaje que tenés que traducir al usuario: «ya tenés "
                "3 proyectos activos, aparcá o terminá uno primero». "
                "Para crear directo como aparcado o terminado, pasá "
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
                "Edita campos de un proyecto existente. Pasale el "
                "`proyecto_id` y los campos que cambian. NO cambies "
                "`estado` por acá — usá `aparcar_proyecto`, "
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
                "activos, falla — traducí el mensaje al usuario "
                "(«ya tenés 3 activos, aparcá o terminá uno antes»)."
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
                "semántico (RAG). Usala cuando el usuario pregunte "
                "por algo que podría estar en sus notas: «¿qué "
                "anoté sobre X?», «búscame mi resumen de Y», "
                "«contame qué decía mi apunte de Z». Devuelve los "
                "apuntes más relevantes con título y un fragmento. "
                "Si la búsqueda no devuelve nada, decílo: NO "
                "inventes contenido."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "consulta": {
                        "type": "string",
                        "description": (
                            "Lo que se está buscando, en lenguaje "
                            "natural. Podés expandir la pregunta "
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
                            "Default 5. Subílo solo si el usuario "
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
                "Revisá el formato (fechas en ISO 8601, ids como UUID) "
                "y volvé a llamarme."
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


async def _crear_apunte(db: Postgrest, args: dict) -> dict[str, Any]:
    try:
        body = ApunteCreate(**args)
    except ValidationError as e:
        return _err_validacion(e)

    payload = body.model_dump(mode="json", exclude_none=True)
    fila = await db.insert("apuntes", payload)
    return _ok(
        {
            "id": fila["id"],
            "titulo": fila["titulo"],
            "etiquetas": fila.get("etiquetas", []),
        }
    )


async def _completar_tarea(db: Postgrest, args: dict) -> dict[str, Any]:
    raw_id = args.get("tarea_id")
    if not raw_id:
        return _error(
            "validacion",
            "Falta el `tarea_id`.",
            sugerencia="Mirá el contexto vivo y volvé a llamarme con el id.",
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
            sugerencia="Revisá la lista actualizada y volvé a intentar.",
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
                "Buscá la tarea en «Tareas completadas hoy» del "
                "contexto y volvé a llamarme con su id."
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
                "Decile al usuario que defina la próxima acción "
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
                "existe. Limpié la referencia. Decile al usuario "
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
            sugerencia="Volvé a llamarme con al menos un campo además del id.",
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
    f"Ya hay {_TOPE_PROYECTOS_ACTIVOS} proyectos activos. Aparcá o "
    "terminá uno primero."
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
                    "Sugerí al usuario que aparque o termine alguno, "
                    "y volvé a llamarme. O creá el nuevo como "
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
            "Para cambiar el estado del proyecto usá "
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
                    "Sugerí al usuario que aparque o termine otro "
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
                "el match es débil — decile al usuario que no "
                "encontraste nada claro en lugar de inventar."
            ),
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


# Mapa de nombre → handler. Mantener sincronizado con TOOL_DEFINITIONS.
_HANDLERS = {
    # Crear
    "crear_tarea": _crear_tarea,
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
    # Solo lectura
    "buscar_apuntes": _buscar_apuntes,
    "consultar_uso": _consultar_uso,
}


# Mapa de nombre → tablas afectadas. El chat lo expone para que la
# app Flutter sepa qué providers invalidar.
TABLAS_AFECTADAS = {
    "crear_tarea": ["tareas"],
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
    "buscar_apuntes": [],  # solo lectura
    "consultar_uso": [],  # solo lectura
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
    except Exception as e:  # noqa: BLE001
        # Nunca propagar — un crash de la tool dejaría al modelo sin
        # contexto. Devolvemos algo que pueda explicar.
        return _error(
            "interno",
            f"Algo falló al ejecutar «{name}» ({type(e).__name__}).",
            sugerencia=(
                "Decile al usuario que algo se rompió en el cerebro "
                "y que reintente en un momento."
            ),
        )
