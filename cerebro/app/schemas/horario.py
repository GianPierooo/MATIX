"""Schemas del plan del día (capa de horario) que consume la app («Hoy»)."""
from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class BloqueRead(BaseModel):
    inicio: str          # "HH:MM" (hora Lima)
    fin: str             # "HH:MM"
    titulo: str
    tipo: str            # clase | evento | ancla | trabajo | skill | tarea
    proyecto: str | None = None
    skill: str | None = None
    nodo_id: UUID | None = None
    tarea_id: UUID | None = None
    set_item_id: UUID | None = None
    tentativo: bool      # True = planificado/ajustable; False = fijo/inmovible


class FueraRead(BaseModel):
    titulo: str
    tipo: str
    motivo: str


class PlanDelDiaRead(BaseModel):
    fecha: str           # ISO date
    despierta: str       # "HH:MM"
    duerme: str          # "HH:MM"
    desde: str | None = None  # "HH:MM" si es replan desde la hora actual
    bloques: list[BloqueRead]
    fuera: list[FueraRead]


class CompletarBloqueRequest(BaseModel):
    tarea_id: UUID | None = None
    nodo_id: UUID | None = None


class SaltarBloqueRequest(BaseModel):
    set_item_id: UUID


class ReplanRequest(BaseModel):
    ahora: datetime | None = None


class BloquePush(BaseModel):
    titulo: str
    inicio: str          # "HH:MM"
    fin: str | None = None


class PushCalendarioRequest(BaseModel):
    # Bloques que ve la app (con horas editadas). Si viene vacío, el cerebro
    # recalcula el plan y empuja los tentativos.
    bloques: list[BloquePush] | None = None
