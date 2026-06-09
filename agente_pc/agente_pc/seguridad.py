"""Rails de seguridad del agente local: validación de rutas (allowlist /
denylist) y ocultamiento de entradas sensibles.

TODO aquí es PURO y determinista: sin red, sin estado global, sin ejecución de
shell. Es EL límite de seguridad del agente y por eso vive aislado y testeado.

Reglas:
  - La allowlist define lo único que el agente puede tocar.
  - La denylist (carpetas de sistema + nombres prohibidos) GANA sobre la
    allowlist: aunque algo caiga dentro de una carpeta permitida, es invisible.
  - Las rutas se resuelven (realpath, symlinks, `..`) ANTES de decidir, para
    que nadie escape de la allowlist con enlaces o `../../`.
"""
from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path

# Nombres de carpeta/archivo prohibidos en CUALQUIER componente de la ruta.
# Comparación en minúsculas. La denylist gana sobre la allowlist.
NOMBRES_PROHIBIDOS: frozenset[str] = frozenset(
    {
        # Llaves y credenciales
        ".ssh",
        ".gnupg",
        ".aws",
        ".azure",
        ".gcloud",
        ".kube",
        ".docker",
        ".password-store",
        "credentials",
        "secrets",
        # Config con secretos / control de versiones
        ".env",
        ".git",
        ".npmrc",
        ".pypirc",
        ".netrc",
        # Perfiles de navegador / datos de apps sensibles
        "appdata",
        "application data",
        "local settings",
        ".mozilla",
        ".thunderbird",
        # Papelera / metadatos de sistema
        "$recycle.bin",
        "system volume information",
    }
)

# Sufijos/prefijos de archivo que nunca deben aparecer en un listado.
_SUFIJOS_SECRETOS = (".pem", ".key", ".pfx", ".p12", ".ppk", ".keystore", ".jks")
_PREFIJOS_SECRETOS = ("id_rsa", "id_ed25519", "id_ecdsa", "id_dsa")


def _raices_sistema() -> list[str]:
    """Raíces bloqueadas por completo (Windows + POSIX), ya normalizadas."""
    candidatas = [
        os.environ.get("SystemRoot", r"C:\Windows"),
        r"C:\Windows",
        r"C:\Program Files",
        r"C:\Program Files (x86)",
        os.environ.get("ProgramData", r"C:\ProgramData"),
        r"C:\ProgramData",
        # POSIX (por si el agente corre en Linux/macOS)
        "/etc",
        "/usr",
        "/bin",
        "/sbin",
        "/var",
        "/boot",
        "/sys",
        "/proc",
    ]
    out: list[str] = []
    for c in candidatas:
        if c:
            out.append(_norm(c))
    return out


@dataclass(frozen=True)
class Veredicto:
    permitida: bool
    motivo: str


def _norm(p: str | os.PathLike) -> str:
    """Ruta absoluta, real (symlinks resueltos) y normalizada para comparar."""
    return os.path.normcase(os.path.realpath(os.path.expanduser(str(p))))


def _dentro_de(hijo_norm: str, padre_norm: str) -> bool:
    try:
        return os.path.commonpath([hijo_norm, padre_norm]) == padre_norm
    except ValueError:
        # Distinta unidad (C: vs D:) → commonpath lanza ValueError.
        return False


def _componentes(ruta_norm: str) -> list[str]:
    return [c.lower().strip("\\/") for c in Path(ruta_norm).parts]


# Se calcula al importar (depende solo del entorno, no de input del usuario).
RAICES_SISTEMA: list[str] = _raices_sistema()


def entrada_oculta(nombre: str) -> bool:
    """¿Esta entrada (archivo/carpeta) debe ocultarse de un listado?

    Oculta secretos aunque vivan dentro de una carpeta permitida.
    """
    n = (nombre or "").strip().lower()
    if not n:
        return True
    if n in NOMBRES_PROHIBIDOS:
        return True
    if n == ".env" or n.startswith(".env."):
        return True
    if n.startswith(_PREFIJOS_SECRETOS):
        return True
    if n.endswith(_SUFIJOS_SECRETOS):
        return True
    return False


def ruta_permitida(ruta: str, allowlist: list[Path]) -> Veredicto:
    """¿Se puede TOCAR esta ruta?

    Orden: denylist de sistema → denylist de nombres → allowlist. La denylist
    gana siempre. Resuelve symlinks/`..` antes de decidir (anti-escape).
    """
    if not ruta or not str(ruta).strip():
        return Veredicto(False, "ruta vacía")

    real = _norm(ruta)

    # 1) Denylist de sistema (gana siempre, aun si está en la allowlist).
    for raiz in RAICES_SISTEMA:
        if real == raiz or _dentro_de(real, raiz):
            return Veredicto(False, "carpeta de sistema")

    # 2) Denylist de nombres en cualquier componente (gana siempre).
    for comp in _componentes(real):
        if comp in NOMBRES_PROHIBIDOS or comp == ".env" or comp.startswith(".env."):
            return Veredicto(False, "componente prohibido")

    # 3) Debe caer dentro de alguna carpeta de la allowlist.
    for permitida in allowlist:
        if _dentro_de(real, _norm(permitida)):
            return Veredicto(True, "ok")

    return Veredicto(False, "fuera de la allowlist")


# ─────────────────────────────────────────────────────────────────────────────
# Fase 6.2 — Denylist de APPS (qué NO se puede LANZAR, aunque esté en la
# allowlist de apps). Esto es distinto de la denylist de RUTAS de arriba:
# aquí no protegemos lectura de archivos, protegemos contra LANZAR procesos
# peligrosos (shells, instaladores, herramientas de sistema, credenciales).
# La denylist GANA sobre la allowlist de apps: aunque el usuario la liste,
# nunca se abre. Es HARDCODED a propósito — no editable por config.
# ─────────────────────────────────────────────────────────────────────────────

# Ejecutables prohibidos por BASENAME (comparación en minúsculas, con y sin
# extensión). Cubre: shells/terminales (un shell = ejecución arbitraria, el
# agujero que toda esta capa evita), intérpretes que serían shell-equivalentes
# si se abren pelados, herramientas de sistema/registro/tareas, instaladores, y
# gestor de credenciales.
APPS_DENYLIST_BASENAMES: frozenset[str] = frozenset(
    {
        # Shells y terminales
        "cmd", "cmd.exe", "powershell", "powershell.exe", "pwsh", "pwsh.exe",
        "bash", "bash.exe", "sh", "sh.exe", "zsh", "fish", "dash",
        "wsl", "wsl.exe", "conhost", "conhost.exe", "wt", "wt.exe",
        "windowsterminal", "windowsterminal.exe", "openconsole", "openconsole.exe",
        "cscript", "cscript.exe", "wscript", "wscript.exe", "mshta", "mshta.exe",
        # Intérpretes (shell-equivalentes si se lanzan sin sandbox)
        "python", "python.exe", "pythonw", "pythonw.exe", "py", "py.exe",
        "node", "node.exe", "ruby", "ruby.exe", "perl", "perl.exe",
        # Herramientas de sistema / registro / tareas / red
        "regedit", "regedit.exe", "regedt32", "regedt32.exe",
        "taskmgr", "taskmgr.exe", "mmc", "mmc.exe", "msconfig", "msconfig.exe",
        "control", "control.exe", "rundll32", "rundll32.exe",
        "regsvr32", "regsvr32.exe", "sc", "sc.exe", "reg", "reg.exe",
        "net", "net.exe", "net1", "net1.exe", "netsh", "netsh.exe",
        "wmic", "wmic.exe", "taskkill", "taskkill.exe", "at", "at.exe",
        "schtasks", "schtasks.exe", "bcdedit", "bcdedit.exe", "diskpart", "diskpart.exe",
        # Instaladores
        "msiexec", "msiexec.exe", "setup", "setup.exe",
        "install", "install.exe", "installer", "installer.exe",
        "unins000", "unins000.exe",
        # Gestor de credenciales / seguridad
        "credwiz", "credwiz.exe", "vaultcmd", "vaultcmd.exe", "keymgr", "keymgr.dll",
        "rundll32.exe,keymgr.dll",  # forma típica de invocar el gestor de credenciales
    }
)


def _dirs_denylist_apps() -> list[str]:
    """Directorios cuyo contenido NUNCA se lanza como app: ahí viven shells y
    herramientas de sistema. Program Files / LocalAppData NO están aquí: las
    apps legítimas (editores, navegadores) viven en esos sitios. En POSIX, /bin
    y /sbin tienen shells; /usr/bin tiene apps legítimas → no se bloquea."""
    out: list[str] = []
    for d in (
        os.environ.get("SystemRoot", r"C:\Windows"),
        r"C:\Windows",
        "/bin",
        "/sbin",
    ):
        if d:
            out.append(_norm(d))
    return out


APPS_DENYLIST_DIRS: list[str] = _dirs_denylist_apps()


def app_denylisted(exe_path: str) -> str | None:
    """¿Este ejecutable está PROHIBIDO de lanzar? Devuelve el motivo o None.

    La denylist GANA sobre cualquier allowlist. Se chequea por basename (corta
    por `/` y `\\` de forma OS-agnóstica, para que funcione con rutas Windows
    aunque el chequeo corra en otro SO — el agente vive en Windows) y por
    directorio de sistema. PURO dado el string."""
    if not exe_path or not str(exe_path).strip():
        return "ruta vacía"
    # Basename OS-agnóstico: corta por ambos separadores.
    base = re.split(r"[/\\]", str(exe_path).strip())[-1].lower()
    raiz = os.path.splitext(base)[0]
    if base in APPS_DENYLIST_BASENAMES or raiz in APPS_DENYLIST_BASENAMES:
        return f"ejecutable de sistema/shell prohibido ({base})"
    real = _norm(exe_path)
    for d in APPS_DENYLIST_DIRS:
        if real == d or _dentro_de(real, d):
            return "vive en un directorio de sistema (shells/herramientas)"
    return None
