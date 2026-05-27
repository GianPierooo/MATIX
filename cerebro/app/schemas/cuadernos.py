from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class CuadernoCreate(BaseModel):
    nombre: str = Field(min_length=1)
    color: str | None = None
    curso_id: UUID | None = None


class CuadernoUpdate(BaseModel):
    nombre: str | None = Field(default=None, min_length=1)
    color: str | None = None
    curso_id: UUID | None = None


class CuadernoRead(BaseModel):
    id: UUID
    nombre: str
    color: str | None = None
    curso_id: UUID | None = None
    creado_en: datetime
