"""Schemas de la memoria personal de Matix."""
from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class MemoriaCreate(BaseModel):
    contenido: str = Field(min_length=1)
    categoria: str | None = None
    esencial: bool = True


class MemoriaUpdate(BaseModel):
    contenido: str | None = Field(default=None, min_length=1)
    categoria: str | None = None
    esencial: bool | None = None


class MemoriaRead(BaseModel):
    id: UUID
    contenido: str
    categoria: str | None = None
    esencial: bool
    creado_en: datetime
    actualizado_en: datetime

    model_config = ConfigDict(from_attributes=True)
