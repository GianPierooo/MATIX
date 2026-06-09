"""Comandos de UNIVERSIDAD — segunda sección de la capa de comandos (2.0 · Fase 2).

Sigue EXACTAMENTE el patrón de `comandos/tareas.py` (Fase 1): cada capacidad es
UN comando con UN handler único, la ÚNICA fuente de su lógica. El endpoint REST
(app) y la tool de la IA son envoltorios delgados sobre estos handlers.

Cubre las tres entidades de Universidad:
  - Cursos:        crear / editar / eliminar / consultar
  - Sesiones de clase: crear (una) / crear_lote (recurrencia) / editar /
                       eliminar / consultar
  - Evaluaciones:  crear / editar / eliminar / consultar

RECURRENCIA DE CLASES (sin tocar G5): una clase "Cálculo lunes y miércoles
8-10" NO usa la recurrencia general de eventos. El modelo de `sesiones_clase`
ya expresa la recurrencia como UNA fila por día de la semana (`dia_semana`
0=lunes … 6=domingo, hora fija). Así "lunes y miércoles" = DOS sesiones. El
comando `crear_sesiones_clase` materializa eso: recibe `dias_semana: [0, 2]` y
crea una sesión por día. No depende de la recurrencia de `crear_evento` (G5);
esa queda para Fase 3 (Calendario).

BORRADO: las tres tablas borran DURO (no tienen papelera, igual que hoy en sus
routers). Por eso los comandos de eliminar son irreversibles; en el canal de la
IA se exige confirmación (ver `_REQUIERE_CONFIRMACION` en tools.py), siguiendo
la regla de seguridad "Matix pide confirmación antes de borrar".
"""
from __future__ import annotations

from datetime import date, datetime
from typing import Any
from uuid import UUID

from pydantic import ValidationError

from ..db import Postgrest
from ..schemas.cursos import CursoCreate, CursoUpdate
from ..schemas.evaluaciones import EvaluacionCreate, EvaluacionUpdate
from ..schemas.sesiones_clase import SesionClaseCreate, SesionClaseUpdate
from . import recurrencia as _recurrencia
from .registro import Comando, RegistroComandos, Riesgo, error, ok

T_CURSOS = "cursos"
T_SESIONES = "sesiones_clase"
T_EVALUACIONES = "evaluaciones"

_DIAS = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]
_MAX_SESIONES = 7  # una semana completa, tope sano del lote de recurrencia


# ── Helpers (mismos que tareas.py; la lógica vive una sola vez por sección) ────


def _uuid(raw: Any) -> str | None:
    try:
        return str(UUID(str(raw)))
    except (ValueError, TypeError):
        return None


def _err_validacion(e: ValidationError) -> dict[str, Any]:
    try:
        primero = e.errors()[0]
        campo = ".".join(str(x) for x in primero.get("loc", ())) or "campo"
        return error("validacion", f"«{campo}»: {primero.get('msg', 'inválido')}")
    except Exception:  # noqa: BLE001
        return error("validacion", "Datos inválidos.")


def _parse_dia(raw: Any) -> date | None:
    if not raw:
        return None
    try:
        return date.fromisoformat(str(raw)[:10])
    except (ValueError, TypeError):
        return None


def _dia_legible(dia: Any) -> str | None:
    try:
        return _DIAS[int(dia)]
    except (ValueError, TypeError, IndexError):
        return None


# ── Cursos ─────────────────────────────────────────────────────────────────────


async def cmd_crear_curso(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    try:
        body = CursoCreate(**params)
    except ValidationError as e:
        return _err_validacion(e)
    fila = await db.insert(T_CURSOS, body.model_dump(mode="json", exclude_none=True))
    return ok(fila)


async def cmd_editar_curso(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    curso_id = _uuid(params.get("curso_id"))
    if curso_id is None:
        return error("validacion", f"El id «{params.get('curso_id')}» no es un UUID válido.")
    campos = {k: v for k, v in params.items() if k != "curso_id"}
    if not campos:
        return error("validacion", "No me pasaste qué campo cambiar.")
    try:
        body = CursoUpdate(**campos)
    except ValidationError as e:
        return _err_validacion(e)
    payload = body.model_dump(mode="json", exclude_unset=True)
    fila = await db.update(T_CURSOS, curso_id, payload)
    if fila is None:
        return error("no_existe", "Ese curso ya no está en el hub.")
    return ok(fila)


async def cmd_eliminar_curso(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    """Borrado DURO (irreversible). Las evaluaciones y sesiones del curso se van
    en cascada a nivel de BD."""
    curso_id = _uuid(params.get("curso_id"))
    if curso_id is None:
        return error("validacion", f"El id «{params.get('curso_id')}» no es un UUID válido.")
    actual = await db.get(T_CURSOS, curso_id)
    if actual is None:
        return error("no_existe", "Ese curso ya no está en el hub.")
    if not await db.delete(T_CURSOS, curso_id):
        return error("no_existe", "Ese curso ya no está en el hub.")
    return ok(actual)


async def cmd_consultar_cursos(db: Postgrest, _params: dict[str, Any]) -> dict[str, Any]:
    cursos = await db.list(T_CURSOS, order="nombre.asc")
    return ok({
        "total": len(cursos),
        "cursos": [
            {
                "id": c.get("id"),
                "nombre": c.get("nombre"),
                "profesor": c.get("profesor"),
            }
            for c in cursos
        ],
    })


# ── Sesiones de clase ───────────────────────────────────────────────────────────


async def cmd_crear_sesion_clase(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    try:
        body = SesionClaseCreate(**params)
    except ValidationError as e:
        return _err_validacion(e)
    fila = await db.insert(T_SESIONES, body.model_dump(mode="json", exclude_none=True))
    return ok(fila)


async def cmd_crear_sesiones_clase(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    """Recurrencia de clase: una sesión por cada día de `dias_semana`.

    "Cálculo lunes y miércoles 8-10" → `dias_semana=[0, 2]` → dos sesiones con
    la MISMA hora. Es la forma nativa de recurrencia del horario (no usa G5)."""
    dias = params.get("dias_semana")
    if not isinstance(dias, list) or not dias:
        return error("validacion", "Pásame `dias_semana`: una lista de días (0=lunes … 6=domingo).")
    # Únicos y ordenados, para no duplicar el mismo día. El modelo de día (0–6)
    # lo valida el motor de recurrencia ÚNICO, el mismo que usan los eventos.
    if not all(_recurrencia.es_indice_valido(d) for d in dias):
        return error("validacion", "`dias_semana` debe ser una lista de enteros (0=lunes … 6=domingo).")
    dias_norm = sorted({int(d) for d in dias})
    if len(dias_norm) > _MAX_SESIONES:
        return error("validacion", f"Demasiados días ({len(dias_norm)}); el máximo es {_MAX_SESIONES}.")
    base = {k: v for k, v in params.items() if k != "dias_semana"}
    validadas: list[dict[str, Any]] = []
    for d in dias_norm:
        try:
            body = SesionClaseCreate(**{**base, "dia_semana": d})
        except ValidationError as e:
            val = _err_validacion(e)
            val["mensaje"] = f"Día {d}: {val['mensaje']}"
            return val
        validadas.append(body.model_dump(mode="json", exclude_none=True))
    creadas = [await db.insert(T_SESIONES, p) for p in validadas]
    return ok({"total": len(creadas), "sesiones": creadas})


async def cmd_editar_sesion_clase(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    sesion_id = _uuid(params.get("sesion_id"))
    if sesion_id is None:
        return error("validacion", f"El id «{params.get('sesion_id')}» no es un UUID válido.")
    campos = {k: v for k, v in params.items() if k != "sesion_id"}
    if not campos:
        return error("validacion", "No me pasaste qué campo cambiar.")
    try:
        body = SesionClaseUpdate(**campos)
    except ValidationError as e:
        return _err_validacion(e)
    payload = body.model_dump(mode="json", exclude_unset=True)
    fila = await db.update(T_SESIONES, sesion_id, payload)
    if fila is None:
        return error("no_existe", "Esa sesión de clase ya no está en el hub.")
    return ok(fila)


async def cmd_eliminar_sesion_clase(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    sesion_id = _uuid(params.get("sesion_id"))
    if sesion_id is None:
        return error("validacion", f"El id «{params.get('sesion_id')}» no es un UUID válido.")
    actual = await db.get(T_SESIONES, sesion_id)
    if actual is None:
        return error("no_existe", "Esa sesión de clase ya no está en el hub.")
    if not await db.delete(T_SESIONES, sesion_id):
        return error("no_existe", "Esa sesión de clase ya no está en el hub.")
    return ok(actual)


async def cmd_consultar_sesiones_clase(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    curso_id = _uuid(params.get("curso_id"))
    sesiones = await db.list(T_SESIONES, order="dia_semana.asc,hora_inicio.asc")
    if curso_id is not None:
        sesiones = [s for s in sesiones if str(s.get("curso_id")) == curso_id]
    cursos = await db.list(T_CURSOS)
    nom_curso = {str(c.get("id")): c.get("nombre") for c in cursos}
    return ok({
        "total": len(sesiones),
        "sesiones": [
            {
                "id": s.get("id"),
                "curso": nom_curso.get(str(s.get("curso_id"))),
                "dia": _dia_legible(s.get("dia_semana")),
                "hora_inicio": s.get("hora_inicio"),
                "hora_fin": s.get("hora_fin"),
                "ubicacion": s.get("ubicacion"),
            }
            for s in sesiones
        ],
    })


# ── Evaluaciones ────────────────────────────────────────────────────────────────


async def cmd_crear_evaluacion(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    try:
        body = EvaluacionCreate(**params)
    except ValidationError as e:
        return _err_validacion(e)
    fila = await db.insert(T_EVALUACIONES, body.model_dump(mode="json", exclude_none=True))
    return ok(fila)


async def cmd_editar_evaluacion(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    evaluacion_id = _uuid(params.get("evaluacion_id"))
    if evaluacion_id is None:
        return error("validacion", f"El id «{params.get('evaluacion_id')}» no es un UUID válido.")
    campos = {k: v for k, v in params.items() if k != "evaluacion_id"}
    if not campos:
        return error("validacion", "No me pasaste qué campo cambiar.")
    try:
        body = EvaluacionUpdate(**campos)
    except ValidationError as e:
        return _err_validacion(e)
    payload = body.model_dump(mode="json", exclude_unset=True)
    fila = await db.update(T_EVALUACIONES, evaluacion_id, payload)
    if fila is None:
        return error("no_existe", "Esa evaluación ya no está en el hub.")
    return ok(fila)


async def cmd_eliminar_evaluacion(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    evaluacion_id = _uuid(params.get("evaluacion_id"))
    if evaluacion_id is None:
        return error("validacion", f"El id «{params.get('evaluacion_id')}» no es un UUID válido.")
    actual = await db.get(T_EVALUACIONES, evaluacion_id)
    if actual is None:
        return error("no_existe", "Esa evaluación ya no está en el hub.")
    if not await db.delete(T_EVALUACIONES, evaluacion_id):
        return error("no_existe", "Esa evaluación ya no está en el hub.")
    return ok(actual)


async def cmd_consultar_evaluaciones(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    """Lectura con filtros: por curso y/o rango de fechas. Responde a «¿qué
    evaluaciones tengo esta semana?» o «¿qué exámenes tengo del curso X?»."""
    curso_id = _uuid(params.get("curso_id"))
    desde = _parse_dia(params.get("desde"))
    hasta = _parse_dia(params.get("hasta"))
    if desde and hasta and hasta < desde:
        desde, hasta = hasta, desde

    evals = await db.list(T_EVALUACIONES, order="fecha.asc")
    cursos = await db.list(T_CURSOS)
    nom_curso = {str(c.get("id")): c.get("nombre") for c in cursos}

    filtradas: list[dict[str, Any]] = []
    for e in evals:
        if curso_id is not None and str(e.get("curso_id")) != curso_id:
            continue
        fdia = _parse_dia(e.get("fecha"))
        if desde and (fdia is None or fdia < desde):
            continue
        if hasta and (fdia is None or fdia > hasta):
            continue
        filtradas.append(e)

    return ok({
        "total": len(filtradas),
        "desde": desde.isoformat() if desde else None,
        "hasta": hasta.isoformat() if hasta else None,
        "evaluaciones": [
            {
                "id": e.get("id"),
                "titulo": e.get("titulo"),
                "tipo": e.get("tipo"),
                "fecha": e.get("fecha"),
                "peso": e.get("peso"),
                "curso": nom_curso.get(str(e.get("curso_id"))),
            }
            for e in filtradas[:40]
        ],
        "truncado": len(filtradas) > 40,
    })


# ── Registro ──────────────────────────────────────────────────────────────────


def registrar(reg: RegistroComandos) -> None:
    """Registra los comandos de Universidad. Lo llama `comandos/__init__.py`."""
    # Cursos
    reg.registrar(Comando(
        "crear_curso", "Crea un curso.", Riesgo.CONSECUENTE, cmd_crear_curso, (T_CURSOS,)))
    reg.registrar(Comando(
        "editar_curso", "Edita campos de un curso.", Riesgo.CONSECUENTE, cmd_editar_curso, (T_CURSOS,)))
    reg.registrar(Comando(
        "eliminar_curso", "Borra un curso (irreversible, arrastra sus evaluaciones y sesiones).",
        Riesgo.CONSECUENTE, cmd_eliminar_curso, (T_CURSOS, T_EVALUACIONES, T_SESIONES)))
    reg.registrar(Comando(
        "consultar_cursos", "Lista los cursos del usuario.", Riesgo.SEGURA, cmd_consultar_cursos, ()))
    # Sesiones de clase
    reg.registrar(Comando(
        "crear_sesion_clase", "Crea una sesión de clase semanal (un día).",
        Riesgo.CONSECUENTE, cmd_crear_sesion_clase, (T_SESIONES,)))
    reg.registrar(Comando(
        "crear_sesiones_clase", "Crea una clase recurrente: una sesión por cada día de la semana.",
        Riesgo.CONSECUENTE, cmd_crear_sesiones_clase, (T_SESIONES,)))
    reg.registrar(Comando(
        "editar_sesion_clase", "Edita una sesión de clase.",
        Riesgo.CONSECUENTE, cmd_editar_sesion_clase, (T_SESIONES,)))
    reg.registrar(Comando(
        "eliminar_sesion_clase", "Borra una sesión de clase (irreversible).",
        Riesgo.CONSECUENTE, cmd_eliminar_sesion_clase, (T_SESIONES,)))
    reg.registrar(Comando(
        "consultar_sesiones_clase", "Lista el horario de clases.",
        Riesgo.SEGURA, cmd_consultar_sesiones_clase, ()))
    # Evaluaciones
    reg.registrar(Comando(
        "crear_evaluacion", "Crea una evaluación (examen/entrega/proyecto) de un curso.",
        Riesgo.CONSECUENTE, cmd_crear_evaluacion, (T_EVALUACIONES,)))
    reg.registrar(Comando(
        "editar_evaluacion", "Edita una evaluación.",
        Riesgo.CONSECUENTE, cmd_editar_evaluacion, (T_EVALUACIONES,)))
    reg.registrar(Comando(
        "eliminar_evaluacion", "Borra una evaluación (irreversible).",
        Riesgo.CONSECUENTE, cmd_eliminar_evaluacion, (T_EVALUACIONES,)))
    reg.registrar(Comando(
        "consultar_evaluaciones", "Lista evaluaciones con filtros (curso, rango de fechas).",
        Riesgo.SEGURA, cmd_consultar_evaluaciones, ()))
