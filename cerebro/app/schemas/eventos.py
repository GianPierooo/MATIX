from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class EventoCreate(BaseModel):
    titulo: str = Field(min_length=1)
    descripcion: str | None = None
    inicia_en: datetime
    termina_en: datetime | None = None
    todo_el_dia: bool = False
    ubicacion: str | None = None
    curso_id: UUID | None = None
    proyecto_id: UUID | None = None
    color: str | None = None
    recordar_en: datetime | None = None


class EventoUpdate(BaseModel):
    titulo: str | None = Field(default=None, min_length=1)
    descripcion: str | None = None
    inicia_en: datetime | None = None
    termina_en: datetime | None = None
    todo_el_dia: bool | None = None
    ubicacion: str | None = None
    curso_id: UUID | None = None
    proyecto_id: UUID | None = None
    color: str | None = None
    recordar_en: datetime | None = None


class EventoRead(BaseModel):
    id: UUID
    titulo: str
    descripcion: str | None = None
    inicia_en: datetime
    termina_en: datetime | None = None
    todo_el_dia: bool
    ubicacion: str | None = None
    curso_id: UUID | None = None
    proyecto_id: UUID | None = None
    color: str | None = None
    recordar_en: datetime | None = None
    eliminado_en: datetime | None = None
    creado_en: datetime
    actualizado_en: datetime
