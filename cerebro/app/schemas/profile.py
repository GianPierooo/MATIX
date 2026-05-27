from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel

Tema = Literal["light", "dark", "system"]


class ProfileCreate(BaseModel):
    nombre: str | None = None
    zona_horaria: str = "America/Lima"
    tema: Tema = "system"


class ProfileUpdate(BaseModel):
    nombre: str | None = None
    zona_horaria: str | None = None
    tema: Tema | None = None


class ProfileRead(BaseModel):
    id: UUID
    nombre: str | None = None
    zona_horaria: str
    tema: Tema
    creado_en: datetime
    actualizado_en: datetime
