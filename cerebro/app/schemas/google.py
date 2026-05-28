from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel


class GoogleStatusRead(BaseModel):
    """Estado de la conexión Google del usuario.

    `conectado=false` cuando todavía no autorizó ninguna cuenta o
    la desconectó. La app lee esto para decidir si pinta el botón
    "Conectar Google" o el estado "Conectado · email".
    """

    conectado: bool
    email: str | None = None
    scopes: list[str] = []
    conectado_en: datetime | None = None
    ultimo_sync_en: datetime | None = None


class GoogleSyncRead(BaseModel):
    """Resumen del último sync ejecutado."""

    email: str
    creados: int
    actualizados: int
    mandados_a_papelera: int
    total_remoto: int
