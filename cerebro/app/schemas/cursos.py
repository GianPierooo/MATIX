from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class CursoCreate(BaseModel):
    nombre: str = Field(min_length=1)
    profesor: str | None = None
    color: str | None = None


class CursoUpdate(BaseModel):
    nombre: str | None = Field(default=None, min_length=1)
    profesor: str | None = None
    color: str | None = None


class CursoRead(BaseModel):
    id: UUID
    nombre: str
    profesor: str | None = None
    color: str | None = None
    creado_en: datetime
    actualizado_en: datetime
