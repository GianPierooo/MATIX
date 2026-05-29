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
    # Capa 4 Paso 2: el cerebro responde si la conexión actual incluye
    # el scope de escritura en Calendar. La app usa esto para decidir
    # si pintar el banner "Reconectar para sincronización bidireccional".
    tiene_escritura: bool = False
    conectado_en: datetime | None = None
    ultimo_sync_en: datetime | None = None


class GoogleSyncRead(BaseModel):
    """Resumen del último sync ejecutado."""

    email: str
    creados: int
    actualizados: int
    mandados_a_papelera: int
    total_remoto: int
    # Eventos manuales del hub que no tenían external_id y se
    # empujaron a Google en este sync (backfill). Sale de 0 cuando
    # el usuario conecta Google después de haber creado eventos a mano.
    empujados_a_google: int = 0
