"""Comandos de TAREAS — la sección piloto de la capa de comandos (2.0 · Fase 1).

Esta es la ÚNICA fuente de la lógica de tareas. Antes la misma lógica vivía
duplicada en `routers/tareas.py` (endpoint de la app) y en `tools.py` (tools de
la IA) — incluso `_avanzar_fecha`/`_crear_siguiente_instancia` estaban copiadas
en ambos lados. Aquí se consolida: el endpoint y la tool son envoltorios
delgados sobre estos handlers.

Comandos:
  - crear_tarea / crear_tareas (lote)
  - editar_tarea   (edición genérica de campos, INCLUYE el toggle de completada
                    con sus efectos: repetición + sync árbol + sync set del día)
  - completar_tarea / reabrir_tarea  (atajos sobre la edición canónica)
  - eliminar_tarea (borrado SUAVE → papelera)  / restaurar_tarea
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import UUID

from pydantic import ValidationError

from ..db import Postgrest
from ..schemas.tareas import TareaCreate, TareaUpdate
from .registro import Comando, RegistroComandos, Riesgo, error, ok

TABLA = "tareas"


# ── Helpers (la ÚNICA copia; antes estaban duplicados en router y tools) ──────


def _ahora_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _uuid(raw: Any) -> str | None:
    try:
        return str(UUID(str(raw)))
    except (ValueError, TypeError):
        return None


def _err_validacion(e: ValidationError) -> dict[str, Any]:
    # Mensaje compacto del primer error (suficiente para UI y LLM).
    try:
        primero = e.errors()[0]
        campo = ".".join(str(x) for x in primero.get("loc", ())) or "campo"
        return error("validacion", f"«{campo}»: {primero.get('msg', 'inválido')}")
    except Exception:  # noqa: BLE001
        return error("validacion", "Datos inválidos.")


def _avanzar_fecha(iso: str, repeticion: str) -> str:
    """Avanza un timestamp ISO 8601 según `repeticion`."""
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
    """Crea una nueva tarea idéntica con `vence_en` (y `recordar_en`) desplazados.
    Mantiene la antelación relativa del recordatorio."""
    nueva: dict[str, Any] = {
        "titulo": original["titulo"],
        "prioridad": original["prioridad"],
        "repeticion": repeticion,
        "vence_en": _avanzar_fecha(original["vence_en"], repeticion),
    }
    for campo in ("nota", "categoria_id", "curso_id", "proyecto_id"):
        if original.get(campo) is not None:
            nueva[campo] = original[campo]
    if original.get("recordar_en"):
        nueva["recordar_en"] = _avanzar_fecha(original["recordar_en"], repeticion)
    await db.insert(TABLA, nueva)


async def _sincronizar_completada(
    db: Postgrest, tarea_id: str, completada: bool
) -> None:
    """Sincroniza el árbol del proyecto y el set del día al completar/reabrir.
    Best-effort: si la tarea no está enlazada a un nodo o al set, no toca nada."""
    estado_arbol = "hecho" if completada else "pendiente"
    estado_set = "hecho" if completada else "aceptado"
    try:
        from ..matix import arbol_proyecto

        await arbol_proyecto.marcar_por_tarea(db, tarea_id=tarea_id, estado=estado_arbol)
    except Exception:  # noqa: BLE001
        pass
    try:
        from ..matix import planificador_diario

        await planificador_diario.marcar_item_por_tarea(
            db, tarea_id=tarea_id, estado=estado_set
        )
    except Exception:  # noqa: BLE001
        pass


async def _aplicar_edicion(
    db: Postgrest, tarea_id: str, actual: dict, campos: dict[str, Any]
) -> dict | None:
    """Núcleo de la edición: valida, actualiza, y aplica los EFECTOS del toggle
    de `completada` (repetición + sync árbol/set). Devuelve la fila o None.

    Es el único lugar donde vive la lógica de "completar"; completar_tarea,
    reabrir_tarea y el editar genérico la comparten, así que el estado queda
    consistente sin importar el camino."""
    try:
        body = TareaUpdate(**campos)
    except ValidationError as e:
        raise _ValidacionError(_err_validacion(e)) from e
    payload = body.model_dump(mode="json", exclude_unset=True)

    # Snapshot del estado PREVIO antes de actualizar: `db.update` puede mutar
    # `actual` en sitio (lo hace el fake de tests; algunos backends también),
    # así que no podemos leer `actual.get("completada")` después del update.
    estaba_completada = bool(actual.get("completada"))
    repeticion = actual.get("repeticion") or payload.get("repeticion")
    tenia_vence = bool(actual.get("vence_en"))

    fila = await db.update(TABLA, tarea_id, payload)
    if fila is None:
        return None

    se_completa_ahora = payload.get("completada") is True and not estaba_completada
    if se_completa_ahora and repeticion and tenia_vence:
        await _crear_siguiente_instancia(db, actual, repeticion)

    if "completada" in payload and bool(payload["completada"]) != estaba_completada:
        await _sincronizar_completada(db, tarea_id, bool(payload["completada"]))

    return fila


class _ValidacionError(Exception):
    """Lleva un dict de error de validación a través de `_aplicar_edicion`."""

    def __init__(self, payload: dict[str, Any]) -> None:
        super().__init__(payload.get("mensaje", "validación"))
        self.payload = payload


# ── Handlers de comando ───────────────────────────────────────────────────────


async def cmd_crear(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    try:
        body = TareaCreate(**params)
    except ValidationError as e:
        return _err_validacion(e)
    payload = body.model_dump(mode="json", exclude_none=True)
    fila = await db.insert(TABLA, payload)
    return ok(fila)


# Tope del lote (mismo guardrail que tenía la tool de IA).
_MAX_LOTE = 12


async def cmd_crear_lote(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    items = params.get("tareas")
    if not isinstance(items, list) or not items:
        return error("validacion", "Pásame `tareas`: una lista con al menos una tarea.")
    if len(items) > _MAX_LOTE:
        return error(
            "validacion",
            f"Son {len(items)} tareas de una — demasiadas. Ofrece el siguiente "
            f"trozo (hasta {_MAX_LOTE}) y el resto por partes.",
        )
    defaults = {
        k: params.get(k)
        for k in ("proyecto_id", "curso_id", "categoria_id")
        if params.get(k)
    }
    validadas: list[dict[str, Any]] = []
    for i, item in enumerate(items):
        if not isinstance(item, dict):
            return error("validacion", f"La tarea #{i + 1} no es un objeto válido.")
        try:
            body = TareaCreate(**{**defaults, **item})
        except ValidationError as e:
            val = _err_validacion(e)
            val["mensaje"] = f"Tarea #{i + 1}: {val['mensaje']}"
            return val
        validadas.append(body.model_dump(mode="json", exclude_none=True))
    creadas = [await db.insert(TABLA, p) for p in validadas]
    return ok({"proyecto_id": defaults.get("proyecto_id"), "tareas": creadas})


async def cmd_editar(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    tarea_id = _uuid(params.get("tarea_id"))
    if tarea_id is None:
        return error("validacion", f"El id «{params.get('tarea_id')}» no es un UUID válido.")
    campos = {k: v for k, v in params.items() if k != "tarea_id"}
    if not campos:
        return error("validacion", "No me pasaste qué campo cambiar.")
    actual = await db.get(TABLA, tarea_id)
    if actual is None:
        return error("no_existe", "Esa tarea ya no está en el hub.")
    try:
        fila = await _aplicar_edicion(db, tarea_id, actual, campos)
    except _ValidacionError as e:
        return e.payload
    if fila is None:
        return error("no_existe", "Esa tarea ya no está en el hub.")
    return ok(fila)


async def cmd_completar(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    tarea_id = _uuid(params.get("tarea_id"))
    if tarea_id is None:
        return error("validacion", f"El id «{params.get('tarea_id')}» no es un UUID válido.")
    actual = await db.get(TABLA, tarea_id)
    if actual is None:
        return error("no_existe", "Esa tarea ya no está en el hub (puede que la borraran).")
    if actual.get("completada"):
        return ok({**actual, "ya_estaba_completada": True, "repetida": False})
    try:
        fila = await _aplicar_edicion(
            db, tarea_id, actual, {"completada": True, "completada_en": _ahora_iso()}
        )
    except _ValidacionError as e:
        return e.payload
    if fila is None:
        return error("interno", "No se pudo marcar la tarea (la BD no la devolvió).")
    return ok({**fila, "repetida": bool(actual.get("repeticion")), "ya_estaba_completada": False})


async def cmd_reabrir(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    tarea_id = _uuid(params.get("tarea_id"))
    if tarea_id is None:
        return error("validacion", f"El id «{params.get('tarea_id')}» no es un UUID válido.")
    actual = await db.get(TABLA, tarea_id)
    if actual is None:
        return error("no_existe", "Esa tarea ya no está en el hub.")
    if not actual.get("completada"):
        return ok({**actual, "ya_estaba_pendiente": True})
    try:
        fila = await _aplicar_edicion(
            db, tarea_id, actual, {"completada": False, "completada_en": None}
        )
    except _ValidacionError as e:
        return e.payload
    if fila is None:
        return error("interno", "No se pudo reabrir la tarea (la BD no la devolvió).")
    return ok({**fila, "ya_estaba_pendiente": False})


async def cmd_eliminar(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    """Borrado SUAVE → papelera (reversible). El borrado DURO (vaciar papelera)
    NO es un comando de IA: vive solo en el endpoint /permanente."""
    tarea_id = _uuid(params.get("tarea_id"))
    if tarea_id is None:
        return error("validacion", f"El id «{params.get('tarea_id')}» no es un UUID válido.")
    fila = await db.update(TABLA, tarea_id, {"eliminado_en": _ahora_iso()})
    if fila is None:
        return error("no_existe", "Esa tarea ya no está en el hub.")
    return ok(fila)


async def cmd_restaurar(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    tarea_id = _uuid(params.get("tarea_id"))
    if tarea_id is None:
        return error("validacion", f"El id «{params.get('tarea_id')}» no es un UUID válido.")
    fila = await db.update(TABLA, tarea_id, {"eliminado_en": None})
    if fila is None:
        return error("no_existe", "Esa tarea ya no está en el hub.")
    return ok(fila)


# ── Subtareas (G6) — la IA gestiona los sub-ítems de una tarea ────────────────

TABLA_SUBTAREAS = "subtareas"


async def cmd_crear_subtarea(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    """Crea una subtarea colgada de una tarea existente."""
    tarea_id = _uuid(params.get("tarea_id"))
    if tarea_id is None:
        return error("validacion", f"El id «{params.get('tarea_id')}» no es un UUID válido.")
    titulo = str(params.get("titulo") or "").strip()
    if not titulo:
        return error("validacion", "La subtarea necesita un título.")
    padre = await db.get(TABLA, tarea_id)
    if padre is None or padre.get("eliminado_en"):
        return error("no_existe", "Esa tarea no está en el hub; no le puedo agregar subtareas.")
    payload: dict[str, Any] = {"tarea_id": tarea_id, "titulo": titulo, "completada": False}
    if isinstance(params.get("orden"), int):
        payload["orden"] = params["orden"]
    fila = await db.insert(TABLA_SUBTAREAS, payload)
    if fila is None:
        return error("interno", "No se pudo crear la subtarea (la BD no la devolvió).")
    return ok(fila)


async def cmd_completar_subtarea(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    """Marca (o desmarca) una subtarea como completada."""
    sub_id = _uuid(params.get("subtarea_id"))
    if sub_id is None:
        return error("validacion", f"El id «{params.get('subtarea_id')}» no es un UUID válido.")
    completada = bool(params.get("completada", True))
    fila = await db.update(TABLA_SUBTAREAS, sub_id, {"completada": completada})
    if fila is None:
        return error("no_existe", "Esa subtarea ya no existe.")
    return ok(fila)


async def cmd_eliminar_subtarea(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    """Borra una subtarea (las subtareas no tienen papelera: borrado directo)."""
    sub_id = _uuid(params.get("subtarea_id"))
    if sub_id is None:
        return error("validacion", f"El id «{params.get('subtarea_id')}» no es un UUID válido.")
    if not await db.delete(TABLA_SUBTAREAS, sub_id):
        return error("no_existe", "Esa subtarea ya no existe.")
    return ok({"eliminada": True, "id": sub_id})


# ── Registro ──────────────────────────────────────────────────────────────────


def registrar(reg: RegistroComandos) -> None:
    """Registra los comandos de Tareas. Lo llama `comandos/__init__.py`."""
    reg.registrar(Comando(
        "crear_tarea", "Crea una tarea.", Riesgo.CONSECUENTE, cmd_crear, ("tareas",)))
    reg.registrar(Comando(
        "crear_tareas", "Crea un lote de tareas.", Riesgo.CONSECUENTE, cmd_crear_lote, ("tareas",)))
    reg.registrar(Comando(
        "editar_tarea", "Edita campos de una tarea (incluye completar/reabrir).",
        Riesgo.CONSECUENTE, cmd_editar, ("tareas",)))
    reg.registrar(Comando(
        "completar_tarea", "Marca una tarea como hecha (repetición + sync).",
        Riesgo.CONSECUENTE, cmd_completar, ("tareas",)))
    reg.registrar(Comando(
        "reabrir_tarea", "Reabre una tarea completada.",
        Riesgo.CONSECUENTE, cmd_reabrir, ("tareas",)))
    reg.registrar(Comando(
        "eliminar_tarea", "Manda una tarea a la papelera (reversible).",
        Riesgo.CONSECUENTE, cmd_eliminar, ("tareas",)))
    reg.registrar(Comando(
        "restaurar_tarea", "Restaura una tarea de la papelera.",
        Riesgo.CONSECUENTE, cmd_restaurar, ("tareas",)))
    reg.registrar(Comando(
        "crear_subtarea", "Crea una subtarea en una tarea.",
        Riesgo.CONSECUENTE, cmd_crear_subtarea, ("subtareas",)))
    reg.registrar(Comando(
        "completar_subtarea", "Marca o desmarca una subtarea como hecha.",
        Riesgo.CONSECUENTE, cmd_completar_subtarea, ("subtareas",)))
    reg.registrar(Comando(
        "eliminar_subtarea", "Borra una subtarea.",
        Riesgo.CONSECUENTE, cmd_eliminar_subtarea, ("subtareas",)))
