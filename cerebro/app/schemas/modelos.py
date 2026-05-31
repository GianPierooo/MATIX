"""Schemas del selector de modelo del LLM de chat."""
from __future__ import annotations

from pydantic import BaseModel


class ModeloInfo(BaseModel):
    id: str
    etiqueta: str
    proveedor: str  # openai | anthropic


class ModelosEstado(BaseModel):
    """Catálogo de modelos + cuál está seleccionado."""

    modelos: list[ModeloInfo]
    seleccionado: str


class SeleccionarModeloRequest(BaseModel):
    modelo: str
