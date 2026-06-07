"""Schemas del plan del día (capa de horario) que consume la app («Hoy»)."""
from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class BloqueRead(BaseModel):
    inicio: str          # "HH:MM" (hora Lima)
    fin: str             # "HH:MM"
    titulo: str
    tipo: str            # clase | evento | transicion | ancla | trabajo | skill | tarea
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


class SugerenciaRead(BaseModel):
    """Una sugerencia ofrecible en un hueco libre (motor determinista)."""
    titulo: str
    tipo: str            # trabajo | skill | tarea
    dur_min: int
    proyecto: str | None = None
    skill: str | None = None
    proyecto_id: UUID | None = None
    nodo_id: UUID | None = None
    tarea_id: UUID | None = None
    set_item_id: UUID | None = None


class HuecoRead(BaseModel):
    """Una ventana libre del día + UNA sugerencia dosificada que cabe (o nada)."""
    inicio: str          # "HH:MM"
    fin: str             # "HH:MM"
    dur_min: int
    etiqueta: str        # duración legible: "1 h 30 min"
    sugerencia: SugerenciaRead | None = None


class PlanDelDiaRead(BaseModel):
    fecha: str           # ISO date
    despierta: str       # "HH:MM"
    duerme: str          # "HH:MM"
    desde: str | None = None  # "HH:MM" si es replan desde la hora actual
    bloques: list[BloqueRead]
    fuera: list[FueraRead]
    sugerencias: list[SugerenciaRead] = []
    huecos: list[HuecoRead] = []


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
    # Ids para enganchar al modelo Tarea↔bloque (no se crea evento): si el bloque
    # ya viene de una tarea/set/nodo, se agenda ESA; si no, se crea una tarea.
    tarea_id: str | None = None
    nodo_id: str | None = None
    set_item_id: str | None = None
    proyecto_id: str | None = None
    tipo: str | None = None


class AgendarRequest(BaseModel):
    # Bloques que ve la app (con horas editadas). Si viene vacío, el cerebro
    # recalcula el plan y agenda los tentativos como TAREAS.
    bloques: list[BloquePush] | None = None
