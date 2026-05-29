"""Schemas del briefing matutino (Capa 8 reducida · Paso 1)."""
from __future__ import annotations

from pydantic import BaseModel


class EventoBriefing(BaseModel):
    hora: str
    hora_fin: str = ""
    titulo: str
    ubicacion: str | None = None
    todo_el_dia: bool = False
    es_de_google: bool = False


class TareaBriefing(BaseModel):
    titulo: str
    prioridad: str = "media"
    contexto: str | None = None
    vence_en: str


class VencidasResumen(BaseModel):
    total: int = 0
    mas_antigua_dias: int = 0


class Alerta(BaseModel):
    tipo: str
    mensaje: str


class BriefingHoyRead(BaseModel):
    """Briefing del día actual del usuario.

    `resumen_corto` está pensado para encajar en el body de una
    notificación local; `texto_para_voz` se pasa tal cual al
    endpoint TTS si el usuario toca "Escuchar".
    """

    fecha: str
    dia_semana: str
    saludo: str
    eventos: list[EventoBriefing] = []
    tareas_hoy: list[TareaBriefing] = []
    tareas_vencidas: VencidasResumen
    alertas: list[Alerta] = []
    resumen_corto: str
    texto_para_voz: str


# ─── Cierre del día (Capa 8 · Paso 2) ────────────────────────────────


class TareaHecha(BaseModel):
    titulo: str
    contexto: str | None = None


class TareaPendiente(BaseModel):
    titulo: str
    prioridad: str = "media"
    contexto: str | None = None


class EventoManana(BaseModel):
    hora: str
    titulo: str
    todo_el_dia: bool = False


class CierreHoyRead(BaseModel):
    """Cierre del día. Mismo contrato que el briefing en cuanto a
    `resumen_corto` (body de notificación) y `texto_para_voz` (TTS),
    pero con secciones de repaso nocturno: lo hecho, lo que quedó,
    lo de mañana, y una frase para soltar."""

    fecha: str
    dia_semana: str
    saludo: str
    hechas: list[TareaHecha] = []
    pendientes_hoy: list[TareaPendiente] = []
    tareas_manana: list[TareaPendiente] = []
    eventos_manana: list[EventoManana] = []
    cierre_frase: str
    resumen_corto: str
    texto_para_voz: str
