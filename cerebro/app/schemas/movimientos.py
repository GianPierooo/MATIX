"""Schemas de `movimientos` (Finanzas-1).

Un movimiento es un ingreso o un gasto: tipo, monto, categoría, fecha y
una nota opcional. El signo lo da el `tipo` (ingreso suma, gasto resta),
así que el `monto` siempre es positivo. El balance y el resumen por mes
los calcula la app sobre esta lista — acá solo es el CRUD base.
"""
from __future__ import annotations

from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field


class MovimientoCreate(BaseModel):
    tipo: Literal["ingreso", "gasto"]
    monto: float = Field(gt=0)
    categoria: str = Field(default="General", min_length=1)
    # Si no se manda, la BD usa la fecha de hoy (current_date).
    fecha: date | None = None
    nota: str = ""


class MovimientoUpdate(BaseModel):
    tipo: Literal["ingreso", "gasto"] | None = None
    monto: float | None = Field(default=None, gt=0)
    categoria: str | None = Field(default=None, min_length=1)
    fecha: date | None = None
    nota: str | None = None


class MovimientoRead(BaseModel):
    id: UUID
    tipo: Literal["ingreso", "gasto"]
    monto: float
    categoria: str
    fecha: date
    nota: str
    creado_en: datetime
    actualizado_en: datetime
