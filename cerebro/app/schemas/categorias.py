from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class CategoriaCreate(BaseModel):
    nombre: str = Field(min_length=1)
    color: str | None = None
    icono: str | None = None


class CategoriaUpdate(BaseModel):
    nombre: str | None = Field(default=None, min_length=1)
    color: str | None = None
    icono: str | None = None


class CategoriaRead(BaseModel):
    id: UUID
    nombre: str
    color: str | None = None
    icono: str | None = None
    creado_en: datetime
