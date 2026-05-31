"""Schemas del selector de modelo del LLM de chat."""
from __future__ import annotations

from pydantic import BaseModel


class ModeloInfo(BaseModel):
    id: str
    etiqueta: str
    proveedor: str  # openai | anthropic


class ParModelos(BaseModel):
    """El par barato/fuerte que usa el modo Automático."""

    barato: str
    fuerte: str


class ModelosEstado(BaseModel):
    """Catálogo de modelos + cuál está seleccionado + el par del modo auto.

    `seleccionado` puede ser un id del catálogo o el literal `"auto"`.
    `par` es el par barato/fuerte vigente (defaults si no se cambió).
    """

    modelos: list[ModeloInfo]
    seleccionado: str
    par: ParModelos


class SeleccionarModeloRequest(BaseModel):
    # Un id del catálogo o `"auto"`.
    modelo: str


class ParRequest(BaseModel):
    """Cambia el par del modo Automático. Ambos opcionales (cambio parcial)."""

    barato: str | None = None
    fuerte: str | None = None
