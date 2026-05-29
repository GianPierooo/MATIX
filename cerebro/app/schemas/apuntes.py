from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, Field


class ApunteCreate(BaseModel):
    titulo: str = Field(min_length=1)
    contenido: str = ""
    cuaderno_id: UUID | None = None
    curso_id: UUID | None = None
    proyecto_id: UUID | None = None
    etiquetas: list[str] = Field(default_factory=list)
    adjuntos: list[dict[str, Any]] = Field(default_factory=list)


class ApunteUpdate(BaseModel):
    titulo: str | None = Field(default=None, min_length=1)
    contenido: str | None = None
    cuaderno_id: UUID | None = None
    curso_id: UUID | None = None
    proyecto_id: UUID | None = None
    etiquetas: list[str] | None = None
    adjuntos: list[dict[str, Any]] | None = None


class ApunteRead(BaseModel):
    id: UUID
    titulo: str
    contenido: str
    cuaderno_id: UUID | None = None
    curso_id: UUID | None = None
    proyecto_id: UUID | None = None
    etiquetas: list[str]
    adjuntos: list[dict[str, Any]]
    eliminado_en: datetime | None = None
    creado_en: datetime
    actualizado_en: datetime


class ApunteDesdeFoto(ApunteRead):
    """Respuesta del endpoint `POST /apuntes/desde-foto`. Es el
    mismo apunte que devuelve la creación normal más dos flags para
    que la UI sepa si el OCR funcionó y, si no, qué decir.

    `ocr_ok=False` no es un error del request — el apunte se creó
    igual con la foto adjunta. Solo significa que `contenido` quedó
    vacío y el usuario tiene que editarlo a mano.
    """

    ocr_ok: bool = True
    mensaje_ocr: str | None = None
