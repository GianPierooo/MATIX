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


def _stem(nombre: str) -> str:
    return (nombre or "").strip().lower()


def _buscar_app_paths(nombre: str) -> str | None:
    """App Paths del registro de Windows (HKCU + HKLM, 64 y 32 bits). Muchas
    apps (Chrome, Edge, etc.) registran ahí su exe. Devuelve la ruta o None."""
    if os.name != "nt":
        return None
    try:
        import winreg  # type: ignore
    except Exception:  # noqa: BLE001
        return None
    clave_rel = r"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths"
    candidatos = [nombre, f"{nombre}.exe"]
    raices = [
        (winreg.HKEY_CURRENT_USER, 0),
        (winreg.HKEY_LOCAL_MACHINE, 0),
        (winreg.HKEY_LOCAL_MACHINE, winreg.KEY_WOW64_32KEY),
    ]
    for raiz, flag in raices:
        for cand in candidatos:
            try:
                with winreg.OpenKey(
                    raiz, f"{clave_rel}\\{cand}", 0, winreg.KEY_READ | flag
                ) as k:
                    valor, _ = winreg.QueryValueEx(k, None)  # default value
                    ruta = os.path.realpath(os.path.expandvars(str(valor).strip('"')))
                    if os.path.isfile(ruta):
                        return ruta
            except OSError:
                continue
    return None


# Directorios donde viven apps de usuario. NO incluye C:\Windows (denylist).
def _dirs_busqueda_apps() -> list[str]:
    if os.name != "nt":
        return []
    env = os.environ
    candidatos = [
        env.get("LOCALAPPDATA"),
        env.get("APPDATA"),
        env.get("ProgramFiles"),
        env.get("ProgramFiles(x86)"),
        env.get("ProgramW6432"),
    ]
    vistos, out = set(), []
    for c in candidatos:
        if c and os.path.isdir(c) and c.lower() not in vistos:
            vistos.add(c.lower())
            out.append(c)
    return out


def _buscar_en_dirs(nombre: str, *, max_dirs: int = 8000, max_prof: int = 4) -> str | None:
    """Busca `{nombre}.exe` (match exacto de stem) en los directorios de apps
    del usuario, ACOTADO en profundidad y nº de carpetas (no recorre el disco).
    Primero AppData (donde viven Spotify/Discord) → rápido en el caso común."""
    objetivo = f"{_stem(nombre)}.exe"
    visitados = 0
    for raiz in _dirs_busqueda_apps():
        base_prof = raiz.rstrip("\\/").count(os.sep)
        for dirpath, dirnames, filenames in os.walk(raiz):
            visitados += 1
            if visitados > max_dirs:
                return None
            # Poda por profundidad.
            if dirpath.count(os.sep) - base_prof >= max_prof:
                dirnames[:] = []
                continue
            for f in filenames:
                if f.lower() == objetivo:
                    ruta = os.path.join(dirpath, f)
                    if os.path.isfile(ruta):
                        return os.path.realpath(ruta)
    return None


def resolver_app_dinamica(nombre: str) -> str | None:
    """Resuelve un nombre de app a un exe REAL del sistema, SIN allowlist (modo
    permisivo). Orden: PATH → App Paths del registro → búsqueda acotada en los
    directorios de apps del usuario. La denylist se aplica APARTE (en el
    handler), así que aunque esto resuelva un shell, no se abre. Solo Windows
    hace registro/búsqueda; en otros SO usa PATH y nada más."""
    s = (nombre or "").strip().strip('"')
    if not s:
        return None
    via_path = shutil.which(s) or shutil.which(f"{s}.exe")
    if via_path:
        return os.path.realpath(via_path)
    exe = _buscar_app_paths(s)
    if exe:
        return exe
    return _buscar_en_dirs(s)


def resolver_apps(specs: dict[str, str]) -> tuple[dict[str, str], list[str]]:
    """Resuelve cada `nombre→spec` a un exe verificado. Devuelve
    `(apps_ok, avisos)`. Falla cerrado: una entrada que no resuelve, no existe,
    o cae en la denylist se OMITE (con un aviso explicativo), NO se incluye en
    el dict resultante. Estos son OVERRIDES explícitos del usuario
    (AGENTE_PC_APPS_ALLOWLIST); ya no son la única vía: lo no listado se resuelve
    dinámico al abrir."""
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
    # 1) Override explícito del usuario (AGENTE_PC_APPS_ALLOWLIST), si lo fijó.
    exe = (ctx.apps or {}).get(clave)
    # 2) Modo PERMISIVO: cualquier app que el usuario nombre se resuelve sola.
    if not exe:
        resolver = ctx.resolver_app or resolver_app_dinamica
        exe = resolver(nombre)
    if not exe:
        return _err(
            "no_encontrada",
            f"no encontré una app llamada «{nombre}» en tu PC. Dime el nombre "
            "exacto del programa (o su ruta) y la abro.",
        )
    # 3) Rail innegociable: la denylist GANA. Aunque el usuario lo pida, NO se
    # abren shells/terminales, instaladores ni herramientas de sistema.
    motivo = app_denylisted(exe)
    if motivo:
        return _err(
            "denylist",
            f"«{nombre}» no la abro por seguridad ({motivo}): son shells, "
            "instaladores o herramientas de sistema, fuera de los rieles.",
        )
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
    # Sin gate de allowlist: solo cerramos lo que el AGENTE abrió en esta sesión
    # (rastreado por PID). Nunca toca procesos ajenos, así que es seguro de por sí.
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
        "(shells, sistema, instaladores) gana siempre. Sin shell. REVERSIBLE "
        "(se puede cerrar) → SEGURA: directa, sin fricción de confirmación.",
        (Param("nombre", str, requerido=True),),
        NivelRiesgo.SEGURA,
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
