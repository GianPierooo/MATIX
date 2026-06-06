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

    # Escotilla de emergencia: por defecto el agente se NIEGA a correr elevado
    # (admin/root). Poner a 1 solo a conciencia.
    agente_pc_permitir_elevado: bool = False

    model_config = SettingsConfigDict(
        env_file=str(RUTA_ENV),
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    @property
    def allowlist(self) -> list[Path]:
        return parsear_allowlist(self.agente_pc_allowlist)


def cargar_config() -> ConfigAgente:
    return ConfigAgente()
