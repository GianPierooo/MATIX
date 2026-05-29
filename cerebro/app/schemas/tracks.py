from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

EstadoTrack = Literal["activo", "pausado"]


class TrackCreate(BaseModel):
    """Crear un track de aprendizaje.

    `estado` por defecto es `"activo"`; al crear activo, el router valida
    el tope de 3 activos. `bloque_actual` / `semana` / `dia` son la
    posición (opcionales al crear).
    """

    nombre: str = Field(min_length=1)
    descripcion: str | None = None
    estado: EstadoTrack = "activo"
    bloque_actual: str | None = None
    semana: int | None = Field(default=None, ge=0)
    dia: int | None = Field(default=None, ge=0)


class TrackUpdate(BaseModel):
    """Editar un track. Todos opcionales. Cambiar `estado` a `activo`
    revalida el tope; fijar posición es editar `bloque_actual`/`semana`/`dia`."""

    nombre: str | None = Field(default=None, min_length=1)
    descripcion: str | None = None
    estado: EstadoTrack | None = None
    bloque_actual: str | None = None
    semana: int | None = Field(default=None, ge=0)
    dia: int | None = Field(default=None, ge=0)


class TrackRead(BaseModel):
    id: UUID
    nombre: str
    descripcion: str | None = None
    estado: EstadoTrack
    bloque_actual: str | None = None
    semana: int | None = None
    dia: int | None = None
    creado_en: datetime
    actualizado_en: datetime

    model_config = ConfigDict(from_attributes=True)
