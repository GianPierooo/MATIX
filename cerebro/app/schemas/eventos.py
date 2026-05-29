from __future__ import annotations

from datetime import date, datetime
from uuid import UUID

from pydantic import BaseModel, Field


class EventoCreate(BaseModel):
    titulo: str = Field(min_length=1)
    descripcion: str | None = None
    inicia_en: datetime
    termina_en: datetime | None = None
    todo_el_dia: bool = False
    ubicacion: str | None = None
    curso_id: UUID | None = None
    proyecto_id: UUID | None = None
    color: str | None = None
    recordar_en: datetime | None = None
    # Recordatorio como offset en minutos antes del inicio (NULL = sin
    # recordatorio, 0 = a la hora). La app lo usa para reprogramar la
    # notificación local; `recordar_en` queda como espejo derivado.
    recordatorio_offset_min: int | None = None
    # Calendario Paso 3: regla de recurrencia (NULL = evento único). La app
    # expande las ocurrencias por rango; aquí solo se guarda/lee la regla.
    recurrencia_freq: str | None = None
    recurrencia_dias_semana: list[int] | None = None
    recurrencia_fin_tipo: str | None = None
    recurrencia_hasta: date | None = None
    recurrencia_conteo: int | None = None


class EventoUpdate(BaseModel):
    titulo: str | None = Field(default=None, min_length=1)
    descripcion: str | None = None
    inicia_en: datetime | None = None
    termina_en: datetime | None = None
    todo_el_dia: bool | None = None
    ubicacion: str | None = None
    curso_id: UUID | None = None
    proyecto_id: UUID | None = None
    color: str | None = None
    recordar_en: datetime | None = None
    recordatorio_offset_min: int | None = None
    recurrencia_freq: str | None = None
    recurrencia_dias_semana: list[int] | None = None
    recurrencia_fin_tipo: str | None = None
    recurrencia_hasta: date | None = None
    recurrencia_conteo: int | None = None


class EventoRead(BaseModel):
    id: UUID
    titulo: str
    descripcion: str | None = None
    inicia_en: datetime
    termina_en: datetime | None = None
    todo_el_dia: bool
    ubicacion: str | None = None
    curso_id: UUID | None = None
    proyecto_id: UUID | None = None
    color: str | None = None
    recordar_en: datetime | None = None
    recordatorio_offset_min: int | None = None
    recurrencia_freq: str | None = None
    recurrencia_dias_semana: list[int] | None = None
    recurrencia_fin_tipo: str | None = None
    recurrencia_hasta: date | None = None
    recurrencia_conteo: int | None = None
    eliminado_en: datetime | None = None
    # Capa 4 Paso 1: origen del evento. "manual" para los creados
    # desde la app, "google" para los sync-eados.
    origen: str = "manual"
    external_id: str | None = None
    external_account: str | None = None
    # Capa 4 Paso 2: timestamp del último estado conocido en Google.
    # NULL para eventos manuales que aún no se empujaron. La app lo
    # usa solo para decidir si pintar el chip "Sincronizado".
    google_updated_at: datetime | None = None
    creado_en: datetime
    actualizado_en: datetime
