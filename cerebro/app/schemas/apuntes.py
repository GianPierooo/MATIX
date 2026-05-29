from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, Field


class ApunteCreate(BaseModel):
    titulo: str = Field(min_length=1)
    contenido: str = ""
    cuaderno_id: UUID | None = None
    curso_id: UUID | None = None
    proyecto_id: UUID | None = None
    etiquetas: list[str] = Field(default_factory=list)
    adjuntos: list[dict[str, Any]] = Field(default_factory=list)


class ApunteUpdate(BaseModel):
    titulo: str | None = Field(default=None, min_length=1)
    contenido: str | None = None
    cuaderno_id: UUID | None = None
    curso_id: UUID | None = None
    proyecto_id: UUID | None = None
    etiquetas: list[str] | None = None
    adjuntos: list[dict[str, Any]] | None = None


class ApunteRead(BaseModel):
    id: UUID
    titulo: str
    contenido: str
    cuaderno_id: UUID | None = None
    curso_id: UUID | None = None
    proyecto_id: UUID | None = None
    etiquetas: list[str]
    adjuntos: list[dict[str, Any]]
    eliminado_en: datetime | None = None
    # Reflote (Capa 7): si está seteado, el apunte ya no se reflota.
    archivado_en: datetime | None = None
    creado_en: datetime
    actualizado_en: datetime
