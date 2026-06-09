"""Fase 6.2 — abrir/cerrar apps del escritorio, SIN shell.

`abrir_app(nombre)` abre un programa de una ALLOWLIST DURA configurable. Solo
apps de la lista; cualquier otra se rechaza. La DENYLIST de `seguridad.py`
(shells, instaladores, herramientas de sistema, credenciales) GANA siempre —
aunque el usuario la liste, nunca se abre.

`cerrar_app(nombre)` cierra de forma ORDENADA (graceful, no force) las
instancias que el agente abrió EN ESTA SESIÓN (rastreadas por PID). Nunca mata
procesos ajenos ni fuerza el cierre (la app puede preguntar por guardar).

CERO ejecución de shell:
  - El lanzador usa `subprocess.Popen([exe, *args], shell=False)`: la lista de
    argumentos NUNCA se interpreta por un shell → no hay inyección posible.
  - No existe ninguna acción que tome un comando crudo. Solo `abrir_app` (de la
    allowlist) y las tareas tipadas (`tareas.py`). Lo que no esté registrado,
    no se puede ejecutar.

Falla cerrado: nombre inválido, app fuera de la allowlist, exe en la denylist,
o fallo de resolución → rechazado, sin lanzar nada.

Las acciones son CONSECUENTES: el registry exige `confirmado=true` (el gate del
lado agente), que solo llega tras el OK del usuario en el sheet de la app.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
from typing import Any

from .registro import AccionDef, Contexto, NivelRiesgo, Param
from .seguridad import app_denylisted

# Nombre de app válido: letras/dígitos/espacio/._-, 1..64 chars. Rechaza
# separadores de ruta y metacaracteres de shell ANTES de buscar en la allowlist
# (defensa extra: el gate real es la pertenencia a la allowlist, pero no
# queremos ni mirar basura como "rm -rf /" o "C:\\evil.exe").
_NOMBRE_OK = re.compile(r"^[A-Za-z0-9 ._\-]{1,64}$")


def _err(tipo: str, mensaje: str, **extra: Any) -> dict[str, Any]:
    return {"ok": False, "tipo": tipo, "mensaje": mensaje, **extra}


# ── Resolución de la allowlist (impuro: toca el FS + aplica denylist) ─────────


def _resolver_uno(spec: str) -> str | None:
    """Resuelve un spec (ruta absoluta o comando del PATH) a un exe REAL que
    existe. None si no resuelve. PURO respecto al estado (solo lee el FS)."""
    s = (spec or "").strip().strip('"')
    if not s:
        return None
    # Ruta (absoluta o con separador): verificar que exista y sea archivo.
    if os.path.isabs(s) or os.sep in s or (os.altsep and os.altsep in s):
        real = os.path.realpath(os.path.expanduser(s))
        return real if os.path.isfile(real) else None
    # Comando pelado: resolver vía PATH.
    encontrado = shutil.which(s)
    return os.path.realpath(encontrado) if encontrado else None


def resolver_apps(specs: dict[str, str]) -> tuple[dict[str, str], list[str]]:
    """Resuelve cada `nombre→spec` a un exe verificado. Devuelve
    `(apps_ok, avisos)`. Falla cerrado: una entrada que no resuelve, no existe,
    o cae en la denylist se OMITE (con un aviso explicativo), NO se incluye en
    el dict resultante. Así el agente solo conoce apps reales y permitidas."""
    resueltas: dict[str, str] = {}
    avisos: list[str] = []
    for nombre, spec in specs.items():
        exe = _resolver_uno(spec)
        if exe is None:
            avisos.append(
                f"app «{nombre}»: no encontré el ejecutable «{spec}» "
                "(¿ruta correcta? ¿está en el PATH?). Omitida."
            )
            continue
        motivo = app_denylisted(exe)
        if motivo:
            avisos.append(
                f"app «{nombre}» → «{exe}»: BLOQUEADA por la denylist "
                f"({motivo}). Omitida — la denylist no es negociable."
            )
            continue
        resueltas[nombre] = exe
    return resueltas, avisos


# ── Lanzador / terminador reales (sin shell) ──────────────────────────────────


def lanzar_proceso(exe: str, args: list[str] | None = None) -> dict[str, Any]:
    """Lanza `exe` con `args` SIN shell. `shell=False` + args como LISTA = cero
    interpolación de shell (no hay inyección). stdin/stdout/stderr a DEVNULL:
    el agente no comparte su entrada/salida con la app (y apps que leen stdin no
    cuelgan). Devuelve `{ok, pid}` o `{ok: False, error}`."""
    try:
        kwargs: dict[str, Any] = {
            "stdin": subprocess.DEVNULL,
            "stdout": subprocess.DEVNULL,
            "stderr": subprocess.DEVNULL,
            "shell": False,  # explícito y NO negociable: jamás shell
            "close_fds": True,
        }
        if os.name != "nt":
            # Desacopla el proceso del agente en POSIX (sesión nueva).
            kwargs["start_new_session"] = True
        proc = subprocess.Popen([exe, *(args or [])], **kwargs)
        return {"ok": True, "pid": proc.pid}
    except (OSError, ValueError) as e:
        return {"ok": False, "error": type(e).__name__}


def terminar_proceso(pid: int) -> bool:
    """Cierre ORDENADO (graceful, NO force) del proceso `pid`.

    - Windows: `taskkill /PID <pid>` SIN `/F` → manda WM_CLOSE; la app puede
      preguntar por guardar. (taskkill se invoca con shell=False y un PID entero
      nuestro como único argumento: sin inyección posible.)
    - POSIX: SIGTERM (15) → la app maneja el cierre limpio.
    Devuelve True si el comando de cierre se mandó OK."""
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return False
    try:
        if os.name == "nt":
            r = subprocess.run(
                ["taskkill", "/PID", str(pid)],
                shell=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return r.returncode == 0
        os.kill(pid, 15)  # SIGTERM
        return True
    except (OSError, ValueError, ProcessLookupError):
        return False


# ── Handlers ──────────────────────────────────────────────────────────────────


def _abrir_app(args: dict[str, Any], ctx: Contexto) -> dict[str, Any]:
    nombre = (args.get("nombre") or "").strip()
    if not nombre:
        return _err("validacion", "necesito el nombre de la app")
    if not _NOMBRE_OK.match(nombre):
        return _err(
            "nombre_invalido",
            "ese nombre no es válido para una app (no uses rutas ni símbolos "
            "raros). Solo abro apps de tu allowlist por su nombre.",
        )
    clave = nombre.lower()
    exe = (ctx.apps or {}).get(clave)
    if not exe:
        return _err(
            "no_permitida",
            f"«{nombre}» no está en tu allowlist de apps; no la abro.",
            permitidas=sorted(ctx.apps or {}),
        )
    # Defensa en profundidad: re-chequear la denylist al lanzar (por si la
    # allowlist trae algo que no debió pasar la resolución).
    motivo = app_denylisted(exe)
    if motivo:
        return _err("denylist", f"«{nombre}» está bloqueada por seguridad ({motivo}).")
    lanzar = ctx.lanzador or lanzar_proceso
    res = lanzar(exe, [])
    if not res.get("ok"):
        return _err("error_lanzar", f"no pude abrir «{nombre}».")
    pid = res.get("pid")
    if pid is not None:
        ctx.procesos.setdefault(clave, []).append(pid)
    return {"ok": True, "tipo": "app_abierta", "app": nombre, "pid": pid}


def _cerrar_app(args: dict[str, Any], ctx: Contexto) -> dict[str, Any]:
    nombre = (args.get("nombre") or "").strip()
    if not nombre:
        return _err("validacion", "necesito el nombre de la app")
    if not _NOMBRE_OK.match(nombre):
        return _err("nombre_invalido", "ese nombre de app no es válido.")
    clave = nombre.lower()
    # Solo cerramos apps que ESTÉN en la allowlist (puedes cerrar lo que abrirías).
    if clave not in (ctx.apps or {}):
        return _err("no_permitida", f"«{nombre}» no está en tu allowlist; no la cierro.")
    pids = list((ctx.procesos or {}).get(clave) or [])
    if not pids:
        return {
            "ok": True,
            "tipo": "nada_que_cerrar",
            "app": nombre,
            "mensaje": "no abrí ninguna instancia de esa app en esta sesión.",
        }
    terminar = ctx.terminador or terminar_proceso
    cerrados = 0
    for pid in pids:
        if terminar(pid):
            cerrados += 1
    # Limpiamos el registro de la sesión para esa app (cerradas o ya muertas).
    ctx.procesos[clave] = []
    return {"ok": True, "tipo": "app_cerrada", "app": nombre, "cerrados": cerrados}


DEFS_APPS: list[AccionDef] = [
    AccionDef(
        "abrir_app",
        "Abre una app del escritorio. SOLO apps de la allowlist; la denylist "
        "(shells, sistema, instaladores) gana siempre. Sin shell.",
        (Param("nombre", str, requerido=True),),
        NivelRiesgo.CONSECUENTE,
        _abrir_app,
    ),
    AccionDef(
        "cerrar_app",
        "Cierra de forma ordenada las instancias de una app de la allowlist "
        "que el agente abrió en esta sesión. Graceful (no fuerza).",
        (Param("nombre", str, requerido=True),),
        NivelRiesgo.CONSECUENTE,
        _cerrar_app,
    ),
]
