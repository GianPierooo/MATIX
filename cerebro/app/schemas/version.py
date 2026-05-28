from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict


class VersionRead(BaseModel):
    """Última versión publicada del APK.

    `build_number` es el campo crítico para la comparación: monótono
    entero (igual al `GITHUB_RUN_NUMBER` que generó el build). La app
    compara su build local contra este y decide si hay update.
    `version` es la cadena human-readable (ej. "1.0.3") que va al
    diálogo de "nueva versión disponible".
    """

    version: str
    build_number: int
    apk_url: str
    notas: str
    sha: str | None = None
    creado_en: datetime

    model_config = ConfigDict(from_attributes=True)


class VersionAusente(BaseModel):
    """Cuando todavía no se publicó ningún APK por este canal (caso
    del primer arranque tras crear la tabla). La app lo trata como
    "no hay update disponible"."""

    disponible: bool = False
