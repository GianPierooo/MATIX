"""Schemas de la config de rituales diarios (Push Capa 3a)."""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

Ritual = Literal["briefing", "cierre"]


class RitualConfigRead(BaseModel):
    ritual: Ritual
    activo: bool
    hora: int
    minuto: int


class RitualConfigUpdate(BaseModel):
    activo: bool | None = None
    hora: int | None = Field(default=None, ge=0, le=23)
    minuto: int | None = Field(default=None, ge=0, le=59)
