"""Schemas de la config de nudges (Push Capa 3b)."""
from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


_INTENSIDADES = ("suave", "medio", "intenso", "maximo")


class NudgesConfigRead(BaseModel):
    activo: bool
    silencio_inicio: int
    silencio_fin: int
    # disponibilidad por día ISO: {"1":{"activo":true,"inicio":8,"fin":22}, …}
    disponibilidad: dict[str, Any] = Field(default_factory=dict)
    modo_prueba: bool = False
    # Intensidad de los avisos (dial en Ajustes): suave | medio | intenso |
    # maximo. La app la mapea al mecanismo Android (heads-up / persistente /
    # full-screen). Default 'intenso' (lo que el dueño quiere).
    intensidad: str = "intenso"


class NudgesConfigUpdate(BaseModel):
    activo: bool | None = None
    silencio_inicio: int | None = Field(default=None, ge=0, le=23)
    silencio_fin: int | None = Field(default=None, ge=0, le=23)
    disponibilidad: dict[str, Any] | None = None
    modo_prueba: bool | None = None
    intensidad: str | None = Field(default=None, pattern="^(suave|medio|intenso|maximo)$")
