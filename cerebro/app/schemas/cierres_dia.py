from __future__ import annotations

from datetime import date, datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class CierreDiaCreate(BaseModel):
    """Crear o sobreescribir el cierre de un día.

    `fecha` es UNIQUE en la BD; el router maneja el conflicto (POST a
    una fecha ya cerrada actualiza el cierre existente en lugar de
    duplicar — UPSERT).
    """

    fecha: date
    items: list[str] = Field(default_factory=list)
    nota_extra: str | None = None


class CierreDiaUpdate(BaseModel):
    items: list[str] | None = None
    nota_extra: str | None = None


class CierreDiaRead(BaseModel):
    id: UUID
    fecha: date
    items: list[str]
    nota_extra: str | None = None
    creado_en: datetime

    model_config = ConfigDict(from_attributes=True)
