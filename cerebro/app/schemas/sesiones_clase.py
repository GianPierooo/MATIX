from __future__ import annotations

from datetime import time
from uuid import UUID

from pydantic import BaseModel, Field


class SesionClaseCreate(BaseModel):
    curso_id: UUID
    dia_semana: int = Field(ge=0, le=6)  # 0=lun … 6=dom
    hora_inicio: time
    hora_fin: time
    ubicacion: str | None = None


class SesionClaseUpdate(BaseModel):
    curso_id: UUID | None = None
    dia_semana: int | None = Field(default=None, ge=0, le=6)
    hora_inicio: time | None = None
    hora_fin: time | None = None
    ubicacion: str | None = None


class SesionClaseRead(BaseModel):
    id: UUID
    curso_id: UUID
    dia_semana: int
    hora_inicio: time
    hora_fin: time
    ubicacion: str | None = None
