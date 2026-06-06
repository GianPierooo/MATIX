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
