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


# ─── Rollover de lo no cumplido (Capa 8) ─────────────────────────────


class PropuestaHuecoRead(BaseModel):
    """El hueco propuesto para retomar una tarea no cumplida."""

    fecha: str
    inicio: str
    fin: str
    cuando: str


class RolloverItemRead(BaseModel):
    """Una tarea no cumplida con su propuesta de reprogramación."""

    tarea_id: str
    titulo: str
    veces_reprogramada: int = 0
    vencio_en: str | None = None
    propuesta: PropuestaHuecoRead | None = None


class SobrecargaRead(BaseModel):
    """Guardrail honesto: cuánto se arrastra y si ya toca re-escopar."""

    sobrecargado: bool = False
    n: int = 0
    peor_titulo: str | None = None
    peor_veces: int = 0
    mensaje: str | None = None
    recomendacion: str | None = None


class RolloverRead(BaseModel):
    """Propuestas de reprogramación + flag de sobrecarga."""

    proposals: list[RolloverItemRead] = []
    sobrecarga: SobrecargaRead | None = None


class CierreHoyRead(BaseModel):
    """Cierre del día. Mismo contrato que el briefing en cuanto a
    `resumen_corto` (body de notificación) y `texto_para_voz` (TTS),
    pero con secciones de repaso nocturno: lo hecho, lo que quedó,
    lo de mañana, una frase para soltar, y el rollover de lo no
    cumplido (propuestas de reprogramación, tocables en la app)."""

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
    rollover: RolloverRead | None = None


# ─── Repaso semanal (Capa 8 · Repaso) ────────────────────────────────


class TareaVencidaRepaso(BaseModel):
    """Una tarea que se pasó de fecha. Lleva `id` para que la app
    permita reprogramarla desde el repaso."""

    id: str
    titulo: str
    contexto: str | None = None
    vence_en: str | None = None


class RepasoSemanalRead(BaseModel):
    """Repaso semanal sintetizado por Matix. `resumen` y `focos` los
    redacta el LLM (balance honesto, sin reproche); el resto son datos
    del hub de los últimos 7 días. `vencidas` trae ids para accionar."""

    semana_desde: str
    semana_hasta: str
    resumen: str
    focos: list[str] = []
    completadas: int = 0
    vencidas: list[TareaVencidaRepaso] = []
    eventos: int = 0
    apuntes_nuevos: int = 0
