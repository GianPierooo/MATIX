"""Schemas de los modos de Matix."""
from __future__ import annotations

from pydantic import BaseModel


class ModoInfo(BaseModel):
    nombre: str
    etiqueta: str
    descripcion: str


class ModosEstado(BaseModel):
    """Lista de modos disponibles + cuál está activo (`null` = normal)."""

    disponibles: list[ModoInfo]
    activo: str | None = None


class ActivarModoRequest(BaseModel):
    modo: str
