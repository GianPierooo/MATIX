"""Schemas de la biblioteca de material de aprendizaje (Fase 1)."""
from __future__ import annotations

from pydantic import BaseModel, Field


class IngestarMaterialRequest(BaseModel):
    """Cuerpo de `POST /material/ingestar`.

    Sube el material de UN documento (ya troceado por el ingestor) a la
    biblioteca, etiquetado por `skill` (carpeta) y `bloque` (archivo).
    Reemplaza lo previo de ese skill+bloque (idempotente). SOLO viaja el
    texto: el archivo original se queda en la PC.
    """

    skill: str = Field(min_length=1)
    bloque: str = Field(min_length=1)
    fuente: str | None = None
    piezas: list[str] = Field(default_factory=list)


class IngestarMaterialResponse(BaseModel):
    """Cuántas piezas se crearon y cuántas se reemplazaron (las que
    había antes de ese skill+bloque)."""

    skill: str
    bloque: str
    creados: int
    reemplazados: int
