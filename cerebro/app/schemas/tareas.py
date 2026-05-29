from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

Prioridad = Literal["alta", "media", "baja"]
Repeticion = Literal["diaria", "semanal", "mensual", "anual"]


class TareaCreate(BaseModel):
    titulo: str = Field(min_length=1)
    nota: str | None = None
    vence_en: datetime | None = None
    prioridad: Prioridad = "media"
    categoria_id: UUID | None = None
    curso_id: UUID | None = None
    proyecto_id: UUID | None = None
    repeticion: Repeticion | None = None
    recordar_en: datetime | None = None


class TareaUpdate(BaseModel):
    # Todos opcionales: solo se envían los campos que el cliente cambia.
    # Pydantic distingue "no enviado" de "enviado=null" vía `exclude_unset`.
    titulo: str | None = Field(default=None, min_length=1)
    nota: str | None = None
    vence_en: datetime | None = None
    prioridad: Prioridad | None = None
    categoria_id: UUID | None = None
    curso_id: UUID | None = None
    proyecto_id: UUID | None = None
    repeticion: Repeticion | None = None
    recordar_en: datetime | None = None
    completada: bool | None = None
    completada_en: datetime | None = None
    # Urgencia-3: bloque de tiempo asignado al planificar el día.
    bloque_inicio: datetime | None = None
    bloque_fin: datetime | None = None


class TareaRead(BaseModel):
    id: UUID
    titulo: str
    nota: str | None = None
    vence_en: datetime | None = None
    prioridad: Prioridad
    categoria_id: UUID | None = None
    curso_id: UUID | None = None
    proyecto_id: UUID | None = None
    repeticion: Repeticion | None = None
    recordar_en: datetime | None = None
    completada: bool
    completada_en: datetime | None = None
    eliminado_en: datetime | None = None
    # Urgencia-3: bloque de tiempo asignado al planificar el día.
    bloque_inicio: datetime | None = None
    bloque_fin: datetime | None = None
    creada_en: datetime
    actualizada_en: datetime

    model_config = ConfigDict(from_attributes=True)
