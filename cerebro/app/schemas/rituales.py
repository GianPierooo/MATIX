"""Schemas de la config de rituales diarios (Push Capa 3a)."""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

Ritual = Literal["briefing", "cierre", "repaso"]


class RitualConfigRead(BaseModel):
    ritual: Ritual
    activo: bool
    hora: int
    minuto: int
    # ISO 1=lun … 7=dom para rituales SEMANALES (repaso). NULL = diario.
    dia_semana: int | None = None


class RitualConfigUpdate(BaseModel):
    activo: bool | None = None
    hora: int | None = Field(default=None, ge=0, le=23)
    minuto: int | None = Field(default=None, ge=0, le=59)
    # Solo aplica a rituales semanales (repaso): qué día ISO corre.
    dia_semana: int | None = Field(default=None, ge=1, le=7)
