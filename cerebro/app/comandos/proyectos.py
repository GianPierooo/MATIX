"""Comandos de PROYECTOS (2.0 · Fase 4).

Sigue el patrón de Fases 1-3: cada acción es UN comando con UN handler único, la
ÚNICA fuente de su lógica; el endpoint de la app y la tool de la IA envuelven el
MISMO handler. Antes esta lógica vivía DUPLICADA entre `routers/proyectos.py`
(tope de 3, prioridad única, coherencia de la acción siguiente, `inactivo_desde`)
y `matix/tools.py` (tope + tope blando de skills, cambios de estado). Aquí se
consolida la UNIÓN de ambas, así UI e IA aplican exactamente las mismas reglas.

Comandos:
  - crear / editar / aparcar / terminar / reactivar / eliminar / consultar
  - acción siguiente (G9): definir_accion_siguiente (DEFINIR/CAMBIAR — nuevo) +
    marcar_accion_siguiente_hecha (migrado de tools.py)
  - completar_avance_proyecto: cierra un nodo del árbol por CUALQUIER camino (UI,
    IA, o el bloque agendado) → un solo punto, % consistente y el motor de
    evolución alimentado (refresca `ultima_actividad_en`).

NO se reescribe la suite de árbol/intake (generar_arbol, intake_proyecto, etc.):
esas tools ya delegan su lógica a módulos (`arbol_proyecto`, `intake_analitico`,
`creacion_proyecto`) y no están duplicadas entre UI e IA (no hay UI para el
árbol). Se mantienen tal cual; este comando solo añade el cierre canónico de
avance y refresca la actividad que alimenta al motor de evolución.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
from uuid import UUID

from pydantic import ValidationError

from ..db import Postgrest
from ..matix import avance as _avance
from ..matix import creacion_proyecto as _creacion
from ..schemas.proyectos import ProyectoCreate, ProyectoUpdate
from .registro import Comando, RegistroComandos, Riesgo, error, ok
from .registro import registro as _registro

TABLA = "proyectos"
TOPE_ACTIVOS = _creacion.TOPE_PROYECTOS_ACTIVOS  # 3
_MSG_TOPE = f"Ya tienes {TOPE_ACTIVOS} proyectos activos: aparca o termina uno primero."


# ── Helpers (la ÚNICA copia; antes en router y en tools) ─────────────────────


def _ahora_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


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


def _msg_prioridad(n: int) -> str:
    return f"Ya tienes un proyecto activo con el número {n}. Elige otro o libera ese primero."


async def _contar_activos(db: Postgrest, *, excluir_id: str | None = None) -> int:
    """Proyectos de TRABAJO activos (es_skill=false): cuentan para el tope duro."""
    activos = await db.list(TABLA, filters={"estado": "activo"})
    activos = [p for p in activos if not p.get("es_skill")]
    if excluir_id:
        activos = [p for p in activos if str(p["id"]) != str(excluir_id)]
    return len(activos)


async def _aviso_skill(db: Postgrest, *, excluir_id: str | None = None) -> str | None:
    """Tope BLANDO de skills: no bloquea, solo avisa (un hobby no se gestiona con
    candado). Devuelve el motivo si excede, o None."""
    activos = await db.list(TABLA, filters={"estado": "activo"})
    skills = _creacion.solo_skills(activos)
    if excluir_id:
        skills = [p for p in skills if str(p["id"]) != str(excluir_id)]
    cap = _creacion.evaluar_capacidad_skill(len(skills))
    return cap["motivo"] if cap.get("excede") else None


async def _prioridad_ocupada(db: Postgrest, prioridad: int, *, excluir_id: str | None = None) -> bool:
    activos = await db.list(TABLA, filters={"estado": "activo"})
    for p in activos:
        if excluir_id and str(p["id"]) == str(excluir_id):
            continue
        if p.get("prioridad") == prioridad:
            return True
    return False


async def _validar_tarea_siguiente(
    db: Postgrest, tarea_id: str, *, proyecto_id: str | None
) -> tuple[dict | None, dict | None]:
    """Devuelve (tarea, error). La tarea debe existir y no pertenecer a OTRO
    proyecto. Si está libre, el caller la vincula con `_vincular_tarea_si_libre`."""
    tarea = await db.get("tareas", tarea_id)
    if tarea is None:
        return None, error("tarea_no_existe", f"La tarea {tarea_id} no existe.")
    dueño = tarea.get("proyecto_id")
    if dueño is not None and str(dueño) != str(proyecto_id):
        return None, error(
            "conflicto",
            "La tarea referenciada ya pertenece a otro proyecto: muévela primero o elige otra.",
        )
    return tarea, None


async def _vincular_tarea_si_libre(db: Postgrest, tarea: dict, proyecto_id: str) -> None:
    if tarea.get("proyecto_id") is None:
        await db.update("tareas", tarea["id"], {"proyecto_id": proyecto_id})


# ── Crear / editar ───────────────────────────────────────────────────────────


async def cmd_crear(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    try:
        body = ProyectoCreate(**params)
    except ValidationError as e:
        return _err_validacion(e)
    payload = body.model_dump(mode="json", exclude_none=True)

    aviso: str | None = None
    es_activo = payload.get("estado", "activo") == "activo"
    if es_activo:
        if payload.get("es_skill"):
            aviso = await _aviso_skill(db)
        elif await _contar_activos(db) >= TOPE_ACTIVOS:
            return error("tope_proyectos", _MSG_TOPE, sugerencia=(
                "Sugiere al usuario aparcar o terminar alguno, o crea el nuevo "
                "como `aparcado` para guardarlo sin activarlo."))
        prio = payload.get("prioridad")
        if prio is not None and await _prioridad_ocupada(db, prio):
            return error("prioridad_ocupada", _msg_prioridad(prio))

    # Coherencia de la acción siguiente (el proyecto aún no existe).
    tsi = payload.get("tarea_siguiente_id")
    tarea_sig: dict | None = None
    if tsi:
        tarea_sig, err = await _validar_tarea_siguiente(db, tsi, proyecto_id=None)
        if err:
            return err

    payload["ultima_actividad_en"] = _ahora_iso()
    fila = await db.insert(TABLA, payload)
    if tarea_sig is not None:
        await _vincular_tarea_si_libre(db, tarea_sig, fila["id"])
    if aviso:
        return ok({**fila, "aviso": aviso})
    return ok(fila)


async def _aplicar_estado(
    db: Postgrest, proyecto_id: str, actual: dict, nuevo_estado: str, payload: dict[str, Any]
) -> dict | None:
    """Mete en `payload` los efectos del cambio de estado (tope al reactivar +
    `inactivo_desde`). Devuelve un dict de error o None."""
    if nuevo_estado == actual.get("estado"):
        return None
    if nuevo_estado == "activo":
        sera_skill = payload.get("es_skill", actual.get("es_skill"))
        if not sera_skill and await _contar_activos(db, excluir_id=proyecto_id) >= TOPE_ACTIVOS:
            return error("tope_proyectos", _MSG_TOPE, sugerencia=(
                "Sugiere aparcar o terminar otro antes de reactivar este."))
        payload["inactivo_desde"] = None
    else:
        payload["inactivo_desde"] = _ahora_iso()
    return None


async def cmd_editar(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    proyecto_id = _uuid(params.get("proyecto_id"))
    if proyecto_id is None:
        return error("validacion", f"El id «{params.get('proyecto_id')}» no es un UUID válido.")
    campos = {k: v for k, v in params.items() if k != "proyecto_id"}
    if not campos:
        return error("validacion", "No me pasaste qué campo cambiar.")
    try:
        body = ProyectoUpdate(**campos)
    except ValidationError as e:
        return _err_validacion(e)
    payload = body.model_dump(mode="json", exclude_unset=True)

    actual = await db.get(TABLA, proyecto_id)
    if actual is None:
        return error("no_existe", "Ese proyecto ya no está en el hub.")

    # Cambio de estado (tope + inactivo_desde).
    nuevo_estado = payload.get("estado")
    if nuevo_estado is not None:
        err = await _aplicar_estado(db, proyecto_id, actual, nuevo_estado, payload)
        if err:
            return err

    # Prioridad única entre activos (sobre el estado resultante).
    estado_res = nuevo_estado if nuevo_estado is not None else actual.get("estado")
    prio_res = payload["prioridad"] if "prioridad" in payload else actual.get("prioridad")
    if estado_res == "activo" and prio_res is not None:
        if await _prioridad_ocupada(db, prio_res, excluir_id=proyecto_id):
            return error("prioridad_ocupada", _msg_prioridad(prio_res))

    # Coherencia de la acción siguiente.
    tarea_sig: dict | None = None
    if payload.get("tarea_siguiente_id"):
        tarea_sig, err = await _validar_tarea_siguiente(
            db, payload["tarea_siguiente_id"], proyecto_id=proyecto_id)
        if err:
            return err

    payload["ultima_actividad_en"] = _ahora_iso()
    fila = await db.update(TABLA, proyecto_id, payload)
    if fila is None:
        return error("no_existe", "Ese proyecto ya no está en el hub.")
    if tarea_sig is not None:
        await _vincular_tarea_si_libre(db, tarea_sig, proyecto_id)
    return ok(fila)


# ── Cambios de estado (atajos sobre la edición de estado canónica) ───────────


async def _cambiar_estado(db: Postgrest, params: dict[str, Any], nuevo_estado: str) -> dict[str, Any]:
    proyecto_id = _uuid(params.get("proyecto_id"))
    if proyecto_id is None:
        return error("validacion", f"El id «{params.get('proyecto_id')}» no es un UUID válido.")
    actual = await db.get(TABLA, proyecto_id)
    if actual is None:
        return error("no_existe", "Ese proyecto ya no está en el hub.")
    if actual.get("estado") == nuevo_estado:
        return ok({**actual, "ya_estaba_asi": True})

    payload: dict[str, Any] = {"estado": nuevo_estado, "ultima_actividad_en": _ahora_iso()}
    aviso: str | None = None
    err = await _aplicar_estado(db, proyecto_id, actual, nuevo_estado, payload)
    if err:
        return err
    if nuevo_estado == "activo" and actual.get("es_skill"):
        aviso = await _aviso_skill(db, excluir_id=proyecto_id)
    fila = await db.update(TABLA, proyecto_id, payload)
    if fila is None:
        return error("interno", "No se pudo cambiar el estado.")
    out = {**fila, "estado_anterior": actual.get("estado")}
    if aviso:
        out["aviso"] = aviso
    return ok(out)


async def cmd_aparcar(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    return await _cambiar_estado(db, params, "aparcado")


async def cmd_terminar(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    return await _cambiar_estado(db, params, "terminado")


async def cmd_reactivar(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    return await _cambiar_estado(db, params, "activo")


async def cmd_eliminar(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    """Borrado DURO (irreversible). Sirve para deshacer una importación; el árbol
    y el perfil caen por FK en cascada."""
    proyecto_id = _uuid(params.get("proyecto_id"))
    if proyecto_id is None:
        return error("validacion", f"El id «{params.get('proyecto_id')}» no es un UUID válido.")
    actual = await db.get(TABLA, proyecto_id)
    if actual is None:
        return error("no_existe", "Ese proyecto ya no está en el hub.")
    if not await db.delete(TABLA, proyecto_id):
        return error("no_existe", "Ese proyecto ya no está en el hub.")
    return ok(actual)


# ── Acción siguiente (G9) ─────────────────────────────────────────────────────


async def cmd_definir_accion_siguiente(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    """DEFINE o CAMBIA la acción siguiente de un proyecto. Pasa `tarea_id` (o
    null para quitarla). La tarea debe existir y no estar colgada de otro
    proyecto; si está libre, se vincula. «La siguiente acción de X es Y»."""
    proyecto_id = _uuid(params.get("proyecto_id"))
    if proyecto_id is None:
        return error("validacion", f"El id «{params.get('proyecto_id')}» no es un UUID válido.")
    proyecto = await db.get(TABLA, proyecto_id)
    if proyecto is None:
        return error("no_existe", "Ese proyecto ya no está en el hub.")

    raw = params.get("tarea_id", params.get("tarea_siguiente_id"))
    if raw in (None, "", "null"):
        # Quitar la acción siguiente.
        fila = await db.update(TABLA, proyecto_id, {
            "tarea_siguiente_id": None, "ultima_actividad_en": _ahora_iso()})
        return ok({**(fila or proyecto), "tarea_siguiente_id": None})
    tarea_id = _uuid(raw)
    if tarea_id is None:
        return error("validacion", f"El id de tarea «{raw}» no es un UUID válido.")
    tarea, err = await _validar_tarea_siguiente(db, tarea_id, proyecto_id=proyecto_id)
    if err:
        return err
    fila = await db.update(TABLA, proyecto_id, {
        "tarea_siguiente_id": tarea_id, "ultima_actividad_en": _ahora_iso()})
    if fila is None:
        return error("no_existe", "Ese proyecto ya no está en el hub.")
    await _vincular_tarea_si_libre(db, tarea, proyecto_id)
    return ok({**fila, "tarea_definida": tarea.get("titulo")})


async def cmd_marcar_accion_siguiente_hecha(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    """Completa la tarea que es la acción siguiente y limpia el puntero. La
    completa por el comando canónico `completar_tarea` (repetición + sync de
    árbol/set), así el % del proyecto queda consistente (D5)."""
    proyecto_id = _uuid(params.get("proyecto_id"))
    if proyecto_id is None:
        return error("validacion", f"El id «{params.get('proyecto_id')}» no es un UUID válido.")
    proyecto = await db.get(TABLA, proyecto_id)
    if proyecto is None:
        return error("no_existe", "Ese proyecto ya no está en el hub.")
    tarea_sig_id = proyecto.get("tarea_siguiente_id")
    if not tarea_sig_id:
        return error("sin_accion_siguiente",
                     f"El proyecto «{proyecto['nombre']}» no tiene una acción siguiente definida ahora mismo.",
                     sugerencia="Dile al usuario que defina la próxima acción siguiente (o usa definir_accion_siguiente).")
    tarea = await db.get("tareas", tarea_sig_id)
    if tarea is None:
        await db.update(TABLA, proyecto_id, {
            "tarea_siguiente_id": None, "ultima_actividad_en": _ahora_iso()})
        return error("inconsistencia",
                     "La acción siguiente apuntaba a una tarea que ya no existe. Limpié la referencia.")
    if not tarea.get("completada"):
        await _registro.ejecutar(db, "completar_tarea", {"tarea_id": tarea_sig_id}, origen="accion_siguiente")
    await db.update(TABLA, proyecto_id, {
        "tarea_siguiente_id": None, "ultima_actividad_en": _ahora_iso()})
    return ok({
        "proyecto_id": proyecto_id,
        "proyecto_nombre": proyecto["nombre"],
        "tarea_completada": tarea["titulo"],
    })


# ── Completar avance (D5 — cierre canónico de un nodo del árbol) ─────────────


async def cmd_completar_avance(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    """Cierra un nodo del árbol (estado=hecho) por CUALQUIER camino (UI, IA, o el
    bloque agendado) y refresca la actividad del proyecto. Punto único para que
    el % de progreso quede consistente y el motor de evolución (estancamiento,
    hitos, re-escopeo) siga alimentado sin importar desde dónde se complete."""
    from ..matix import arbol_proyecto

    raw_nodo = params.get("nodo_id")
    if not raw_nodo:
        return error("validacion", "Falta el `nodo_id`.")
    nodo_id = str(raw_nodo)
    estado = params.get("estado") or "hecho"
    # Marca el nodo (el % del proyecto se deriva de los estados de los nodos).
    await arbol_proyecto.actualizar_nodo(db, nodo_id=nodo_id, campos={"estado": estado})
    nodo = await db.get("arbol_nodos", nodo_id)
    proyecto_id = (nodo or {}).get("proyecto_id")
    avance_pct: int | None = None
    if proyecto_id:
        # Refrescar la actividad: completar un nodo CUENTA como avance del
        # proyecto (alimenta `estancado()` del motor de evolución). Best-effort.
        try:
            await db.update(TABLA, str(proyecto_id), {"ultima_actividad_en": _ahora_iso()})
        except Exception:  # noqa: BLE001
            pass
        try:
            nodos = await db.list("arbol_nodos", filters={"proyecto_id": str(proyecto_id)})
            avance_pct = _avance.porcentaje(nodos)
        except Exception:  # noqa: BLE001
            pass
    return ok({"nodo_id": nodo_id, "proyecto_id": proyecto_id, "estado": estado, "avance": avance_pct})


# ── Consultar (lectura) ───────────────────────────────────────────────────────


def _dias_inactivo(proyecto: dict, ahora: datetime) -> int | None:
    ult = proyecto.get("ultima_actividad_en")
    if not isinstance(ult, str) or not ult:
        return None
    try:
        dt = datetime.fromisoformat(ult.replace("Z", "+00:00"))
        return (ahora - dt).days
    except Exception:  # noqa: BLE001
        return None


async def cmd_consultar(db: Postgrest, params: dict[str, Any]) -> dict[str, Any]:
    estado = params.get("estado") or "activo"
    if estado not in ("activo", "aparcado", "terminado", "todos"):
        estado = "activo"
    en_riesgo = bool(params.get("en_riesgo"))
    proyectos = await db.list(TABLA)
    ahora = datetime.now(timezone.utc)
    out: list[dict[str, Any]] = []
    for p in proyectos:
        est = p.get("estado")
        dias = _dias_inactivo(p, ahora)
        riesgo = est == "activo" and dias is not None and dias >= 3
        if en_riesgo:
            if not riesgo:
                continue
        elif estado != "todos" and est != estado:
            continue
        out.append({
            "id": p.get("id"), "nombre": p.get("nombre"), "estado": est,
            "prioridad": p.get("prioridad"), "linea_meta": p.get("linea_meta"),
            "dias_inactivo": dias, "en_riesgo": riesgo,
        })
    out.sort(key=lambda x: x.get("prioridad") or 99)
    return ok({"total": len(out), "en_riesgo_solicitado": en_riesgo, "proyectos": out})


# ── Registro ──────────────────────────────────────────────────────────────────


def registrar(reg: RegistroComandos) -> None:
    """Registra los comandos de Proyectos. Lo llama `comandos/__init__.py`."""
    reg.registrar(Comando(
        "crear_proyecto", "Crea un proyecto (valida tope de 3 activos).",
        Riesgo.CONSECUENTE, cmd_crear, ("proyectos",)))
    reg.registrar(Comando(
        "editar_proyecto", "Edita campos de un proyecto (incluye estado).",
        Riesgo.CONSECUENTE, cmd_editar, ("proyectos",)))
    reg.registrar(Comando(
        "aparcar_proyecto", "Aparca un proyecto activo.",
        Riesgo.CONSECUENTE, cmd_aparcar, ("proyectos",)))
    reg.registrar(Comando(
        "terminar_proyecto", "Marca un proyecto como terminado.",
        Riesgo.CONSECUENTE, cmd_terminar, ("proyectos",)))
    reg.registrar(Comando(
        "reactivar_proyecto", "Reactiva un proyecto (valida tope de 3).",
        Riesgo.CONSECUENTE, cmd_reactivar, ("proyectos",)))
    reg.registrar(Comando(
        "eliminar_proyecto", "Borra un proyecto y todo lo suyo (irreversible).",
        Riesgo.CONSECUENTE, cmd_eliminar, ("proyectos",)))
    reg.registrar(Comando(
        "definir_accion_siguiente", "Define o cambia la acción siguiente de un proyecto.",
        Riesgo.CONSECUENTE, cmd_definir_accion_siguiente, ("proyectos", "tareas")))
    reg.registrar(Comando(
        "marcar_accion_siguiente_hecha", "Completa la acción siguiente y limpia el puntero.",
        Riesgo.CONSECUENTE, cmd_marcar_accion_siguiente_hecha, ("proyectos", "tareas")))
    reg.registrar(Comando(
        "completar_avance_proyecto", "Cierra un nodo del plan (avance/hito) por cualquier camino.",
        Riesgo.CONSECUENTE, cmd_completar_avance, ("arbol_nodos", "proyectos")))
    reg.registrar(Comando(
        "consultar_proyectos", "Lista proyectos (filtra por estado / en riesgo).",
        Riesgo.SEGURA, cmd_consultar, ()))
