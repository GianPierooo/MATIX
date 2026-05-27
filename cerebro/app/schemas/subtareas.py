from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class SubtareaCreate(BaseModel):
    tarea_id: UUID
    titulo: str = Field(min_length=1)
    completada: bool = False
    orden: int = 0


class SubtareaUpdate(BaseModel):
    titulo: str | None = Field(default=None, min_length=1)
    completada: bool | None = None
    orden: int | None = None


class SubtareaRead(BaseModel):
    id: UUID
    tarea_id: UUID
    titulo: str
    completada: bool
    orden: int
    creada_en: datetime
