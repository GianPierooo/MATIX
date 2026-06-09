"""Config del agente local. Lee de agente_pc/.env (GITIGNORED).

El secreto AGENTE_PC_TOKEN NO tiene default real: si está vacío, el daemon se
niega a arrancar (no hay conexión anónima al cerebro).
"""
from __future__ import annotations

import os
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

# Raíz del agente = carpeta que contiene este paquete (agente_pc/). Aquí viven
# .env y audit.log.
RAIZ = Path(__file__).resolve().parents[1]
RUTA_ENV = RAIZ / ".env"
RUTA_AUDIT = RAIZ / "audit.log"


def parsear_allowlist(crudo: str) -> list[Path]:
    """Convierte el string de AGENTE_PC_ALLOWLIST en rutas absolutas resueltas.

    Separadores tolerados: ';' y saltos de línea. No usamos ':' porque en
    Windows aparece en 'C:\\...'. Expande '~' al home del usuario.
    """
    if not crudo:
        return []
    piezas = [p.strip() for tramo in crudo.splitlines() for p in tramo.split(";")]
    rutas: list[Path] = []
    for p in piezas:
        if p:
            rutas.append(Path(os.path.realpath(os.path.expanduser(p))))
    return rutas


def parsear_apps(crudo: str) -> dict[str, str]:
    """Convierte AGENTE_PC_APPS_ALLOWLIST (Fase 6.2) en un dict nombre→spec.

    Formato de cada entrada: `nombre=spec` donde `spec` es una ruta absoluta o
    un comando del PATH. También se acepta una entrada sin `=` (un comando
    pelado como 'chrome'), en cuyo caso nombre == spec. Separadores: ';' y
    saltos de línea. El nombre se normaliza a minúsculas (la búsqueda en el
    agente es case-insensitive). NO resuelve ni valida acá — eso lo hace
    `apps.resolver_apps` (que sí toca el FS y aplica la denylist). PURO."""
    if not crudo:
        return {}
    out: dict[str, str] = {}
    piezas = [p.strip() for tramo in crudo.splitlines() for p in tramo.split(";")]
    for p in piezas:
        if not p:
            continue
        if "=" in p:
            nombre, _, spec = p.partition("=")
            nombre, spec = nombre.strip().lower(), spec.strip()
        else:
            # Comando pelado: el nombre es el propio comando.
            nombre, spec = p.strip().lower(), p.strip()
        if nombre and spec:
            out[nombre] = spec
    return out


class ConfigAgente(BaseSettings):
    # Secreto compartido con el cerebro (lo valida en el handshake del WS).
    agente_pc_token: str = ""

    # URL del cerebro (WebSocket sobre TLS). Debe ser wss:// y el host debe
    # coincidir con host_esperado (verificación anti-impostor del spec).
    cerebro_ws_url: str = "wss://matix-production.up.railway.app/api/v1/agente/ws"
    host_esperado: str = "matix-production.up.railway.app"

    # Allowlist de carpetas (separadas por ';' o saltos de línea). El agente
    # SOLO ve lo que cae dentro. La denylist gana por encima de esto.
    agente_pc_allowlist: str = ""

    # Allowlist de APPS (Fase 6.2): `nombre=ruta_o_comando` separadas por ';' o
    # saltos de línea. SOLO estas apps se pueden abrir; la denylist (shells,
    # instaladores, sistema, credenciales) gana siempre.
    agente_pc_apps_allowlist: str = ""

    # Escotilla de emergencia: por defecto el agente se NIEGA a correr elevado
    # (admin/root). Poner a 1 solo a conciencia.
    agente_pc_permitir_elevado: bool = False

    # Tope de lectura de texto (leer_archivo), en KB. Archivos más grandes se
    # leen truncados. Evita volcar archivos enormes por el canal.
    agente_pc_max_lectura_kb: int = 256

    model_config = SettingsConfigDict(
        env_file=str(RUTA_ENV),
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    @property
    def allowlist(self) -> list[Path]:
        return parsear_allowlist(self.agente_pc_allowlist)

    @property
    def apps_specs(self) -> dict[str, str]:
        """Specs de apps SIN resolver (nombre→ruta/comando). La resolución +
        denylist la aplica `apps.resolver_apps` al construir el contexto."""
        return parsear_apps(self.agente_pc_apps_allowlist)


def cargar_config() -> ConfigAgente:
    return ConfigAgente()
