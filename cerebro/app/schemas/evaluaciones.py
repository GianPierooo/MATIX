from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

TipoEvaluacion = Literal["entrega", "examen", "proyecto", "otro"]


class EvaluacionCreate(BaseModel):
    curso_id: UUID
    titulo: str = Field(min_length=1)
    tipo: TipoEvaluacion
    fecha: datetime
    descripcion: str | None = None
    peso: float | None = None
    nota_obtenida: float | None = None
    nota_maxima: float | None = None  # default 20 a nivel de BD
    recordar_en: datetime | None = None


class EvaluacionUpdate(BaseModel):
    curso_id: UUID | None = None
    titulo: str | None = Field(default=None, min_length=1)
    tipo: TipoEvaluacion | None = None
    fecha: datetime | None = None
    descripcion: str | None = None
    peso: float | None = None
    nota_obtenida: float | None = None
    nota_maxima: float | None = None
    recordar_en: datetime | None = None


class EvaluacionRead(BaseModel):
    id: UUID
    curso_id: UUID
    titulo: str
    tipo: TipoEvaluacion
    fecha: datetime
    descripcion: str | None = None
    peso: float | None = None
    nota_obtenida: float | None = None
    nota_maxima: float | None = None
    recordar_en: datetime | None = None
    creada_en: datetime
    actualizada_en: datetime
