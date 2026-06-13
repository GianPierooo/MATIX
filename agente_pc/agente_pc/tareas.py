"""Fase 6.2 — tareas tipadas predefinidas.

`ejecutar_tarea(nombre, params)` ejecuta SOLO tareas REGISTRADAS aquí, cada una
componiendo primitivas seguras (abrir apps de la allowlist, abrir carpetas
permitidas con un editor). NUNCA comandos arbitrarios, NUNCA shell: si el modelo
quiere algo fuera del registro de tareas, no puede — punto.

Extensible: agregar una tarea nueva = registrar un `TareaDef` más (con sus
parámetros tipados y un handler que solo use las primitivas seguras). El
transporte y el cerebro no cambian.

Falla cerrado: tarea no registrada, parámetros faltantes/mal tipados, carpeta
no permitida o app fuera de la allowlist → rechazado, sin lanzar nada.

`ejecutar_tarea` es CONSECUENTE: el registry exige `confirmado=true` (el gate
del lado agente), igual que las demás acciones que lanzan o mutan.
"""
from __future__ import annotations

import logging
import os
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

from . import apps as _apps
from .registro import AccionDef, Contexto, NivelRiesgo, Param
from .seguridad import app_denylisted, ruta_permitida

log = logging.getLogger("matix.agente")


@dataclass(frozen=True)
class TareaDef:
    """Una tarea predefinida: nombre, descripción, parámetros tipados y un
    handler que SOLO usa primitivas seguras."""

    nombre: str
    descripcion: str
    parametros: tuple[Param, ...]
    handler: Callable[[dict[str, Any], Contexto], dict[str, Any]]


def _err(tipo: str, mensaje: str, **extra: Any) -> dict[str, Any]:
    return {"ok": False, "tipo": tipo, "mensaje": mensaje, **extra}


def _validar_params(tarea: TareaDef, params: dict[str, Any]) -> tuple[bool, str]:
    """Valida los params de una tarea contra sus specs (requerido + tipo)."""
    for p in tarea.parametros:
        presente = p.nombre in params and params[p.nombre] not in (None, "")
        if p.requerido and not presente:
            return False, f"falta el parámetro «{p.nombre}»"
        if p.nombre in params and params[p.nombre] is not None:
            if not isinstance(params[p.nombre], p.tipo):
                return False, f"«{p.nombre}» debe ser {p.tipo.__name__}"
    return True, ""


# ── Primitiva compartida: abrir una app de la allowlist (con args opcionales) ─


def _abrir(ctx: Contexto, nombre_app: str, args_exe: list[str] | None = None) -> dict[str, Any]:
    """Abre `nombre_app` (debe estar en la allowlist y NO en la denylist),
    opcionalmente con argumentos (p. ej. una carpeta para el editor). Rastrea el
    PID en `ctx.procesos`. Falla cerrado."""
    clave = (nombre_app or "").strip().lower()
    if not clave:
        return _err("validacion", "falta el nombre de la app")
    exe = (ctx.apps or {}).get(clave)
    if not exe:
        return _err("app_no_permitida", f"«{nombre_app}» no está en la allowlist de apps")
    motivo = app_denylisted(exe)
    if motivo:
        return _err("denylist", f"«{nombre_app}» está bloqueada ({motivo})")
    lanzar = ctx.lanzador or _apps.lanzar_proceso
    res = lanzar(exe, list(args_exe or []))
    if not res.get("ok"):
        return _err("error_lanzar", f"no pude abrir «{nombre_app}»")
    pid = res.get("pid")
    if pid is not None:
        ctx.procesos.setdefault(clave, []).append(pid)
    return {"ok": True, "app": nombre_app, "pid": pid}


# ── Tareas de ejemplo (extensible: registra más abajo) ────────────────────────


def _tarea_sesion_de_foco(params: dict[str, Any], ctx: Contexto) -> dict[str, Any]:
    """Abre un conjunto de apps de la allowlist para una sesión de foco.
    `params["apps"]` = lista separada por comas de nombres de apps (todas deben
    estar en la allowlist). Falla cerrado por app: reporta cuáles abrió y cuáles
    no, sin reventar el resto."""
    crudo = (params.get("apps") or "").strip()
    nombres = [a.strip() for a in crudo.split(",") if a.strip()]
    if not nombres:
        return _err(
            "validacion",
            "dame `apps`: una lista separada por comas de apps de tu allowlist.",
        )
    abiertas: list[str] = []
    fallidas: list[dict[str, str]] = []
    for n in nombres:
        r = _abrir(ctx, n)
        if r.get("ok"):
            abiertas.append(n)
        else:
            fallidas.append({"app": n, "motivo": r.get("tipo", "error")})
    # ok si al menos una abrió; reportamos el detalle para transparencia.
    return {
        "ok": bool(abiertas),
        "tipo": "sesion_de_foco",
        "abiertas": abiertas,
        "fallidas": fallidas,
    }


def _tarea_abrir_proyecto(params: dict[str, Any], ctx: Contexto) -> dict[str, Any]:
    """Abre una carpeta de proyecto (PERMITIDA) con un editor de la allowlist.
    Compone el rail de carpetas (`ruta_permitida`) con el de apps. El editor se
    lanza con la carpeta REAL como argumento (sin shell)."""
    carpeta = (params.get("carpeta") or "").strip()
    editor = (params.get("editor") or "").strip()
    if not carpeta or not editor:
        return _err(
            "validacion",
            "necesito `carpeta` (permitida) y `editor` (app de tu allowlist).",
        )
    # La carpeta DEBE estar en la allowlist de carpetas (reusa el rail existente).
    if not ruta_permitida(carpeta, ctx.allowlist).permitida:
        return _err("rechazada", "esa carpeta no está permitida")
    real = os.path.realpath(os.path.expanduser(carpeta))
    if not os.path.isdir(real):
        return _err("no_existe", "no es una carpeta accesible")
    r = _abrir(ctx, editor, [real])
    if not r.get("ok"):
        return r  # propaga el motivo (app_no_permitida / denylist / error_lanzar)
    return {
        "ok": True,
        "tipo": "abrir_proyecto",
        "carpeta": real,
        "editor": editor,
        "pid": r.get("pid"),
    }


_TAREAS: dict[str, TareaDef] = {}


def _registrar(t: TareaDef) -> None:
    if t.nombre in _TAREAS:
        raise ValueError(f"tarea duplicada: {t.nombre}")
    _TAREAS[t.nombre] = t


_registrar(
    TareaDef(
        "sesion_de_foco",
        "Abre un conjunto de apps de la allowlist para enfocarte.",
        (Param("apps", str, requerido=True, descripcion="apps separadas por comas"),),
        _tarea_sesion_de_foco,
    )
)
_registrar(
    TareaDef(
        "abrir_proyecto",
        "Abre una carpeta de proyecto (permitida) con un editor de la allowlist.",
        (
            Param("carpeta", str, requerido=True),
            Param("editor", str, requerido=True),
        ),
        _tarea_abrir_proyecto,
    )
)


def tareas_registradas() -> list[str]:
    return sorted(_TAREAS)


# ── Acción ejecutar_tarea ─────────────────────────────────────────────────────


def _ejecutar_tarea(args: dict[str, Any], ctx: Contexto) -> dict[str, Any]:
    nombre = (args.get("nombre") or "").strip()
    if not nombre:
        return _err("validacion", "necesito el `nombre` de la tarea")
    tarea = _TAREAS.get(nombre)
    if tarea is None:
        # CERO comandos arbitrarios: si no está registrada, no se ejecuta.
        return _err(
            "no_registrada",
            f"no existe la tarea «{nombre}»; solo ejecuto tareas predefinidas.",
            registradas=tareas_registradas(),
        )
    params = args.get("params") or {}
    if not isinstance(params, dict):
        return _err("validacion", "`params` debe ser un objeto")
    ok, motivo = _validar_params(tarea, params)
    if not ok:
        return _err("validacion", motivo)
    try:
        resultado = tarea.handler(params, ctx)
        if not isinstance(resultado, dict):
            return _err("interno", "la tarea no devolvió un dict")
        return resultado
    except Exception as e:  # noqa: BLE001 — nunca propagar al transporte
        # Traceback REAL al log (no solo el tipo): si una tarea falla, hay que
        # poder diagnosticar por qué, no quedarnos con «falló X».
        log.exception("tarea «%s» lanzó excepción", nombre)
        return _err("interno", f"falló la tarea «{nombre}»: {type(e).__name__}: {e}")


DEFS_TAREAS: list[AccionDef] = [
    AccionDef(
        "ejecutar_tarea",
        "Ejecuta una TAREA PREDEFINIDA y tipada (no comandos arbitrarios). "
        "Solo tareas registradas; compone primitivas seguras.",
        (
            Param("nombre", str, requerido=True),
            Param("params", dict, requerido=False),
        ),
        NivelRiesgo.CONSECUENTE,
        _ejecutar_tarea,
    ),
]
