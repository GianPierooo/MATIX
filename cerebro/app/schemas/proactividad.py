"""Schemas del dial de proactividad (Capa 8)."""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

Nivel = Literal["suave", "equilibrado", "exigente"]


class ProactividadConfigRead(BaseModel):
    activo: bool
    nivel: Nivel
    lead_libre_min: int


class ProactividadConfigUpdate(BaseModel):
    activo: bool | None = None
    nivel: Nivel | None = None
    lead_libre_min: int | None = Field(default=None, ge=5, le=180)
