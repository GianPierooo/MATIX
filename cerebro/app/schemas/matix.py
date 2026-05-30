from __future__ import annotations

from datetime import date
from typing import Literal

from pydantic import BaseModel, Field


class MensajeChat(BaseModel):
    """Un mensaje del historial. `rol` es `user` o `assistant`."""

    rol: Literal["user", "assistant"]
    contenido: str


class ChatRequest(BaseModel):
    """Cuerpo del endpoint `/matix/chat`.

    `imagen`, si viene, es un data URL (`data:image/...;base64,...`) que
    se adjunta al mensaje para que el modelo de visión la vea. Va al
    servidor a propósito (distinto del OCR on-device): para entender la
    imagen hace falta el modelo. Solo viaja en ESE turno; no se guarda
    en el historial.
    """

    historial: list[MensajeChat] = Field(default_factory=list)
    mensaje: str = Field(min_length=1)
    imagen: str | None = None


class TranscripcionResponse(BaseModel):
    """Respuesta del endpoint `/matix/transcribir`.

    Solo devolvemos el texto. La app lo deja en el campo del composer
    para que el usuario lo valide y mande con el flujo normal.
    """

    texto: str


class VozRequest(BaseModel):
    """Cuerpo del endpoint `/matix/voz` (text-to-speech).

    `voz` es opcional; el default `onyx` se eligió en Capa 2 Paso 5.1
    como voz masculina grave estándar de Matix. Otras válidas en
    OpenAI: `alloy`, `echo`, `fable`, `nova`, `shimmer`.
    """

    texto: str = Field(min_length=1, max_length=4096)
    voz: str = "onyx"


class CapturaApunteRequest(BaseModel):
    """Cuerpo del endpoint `/matix/capturar-apunte`.

    `texto` es la idea ya transcrita (Whisper) que se dictó desde la
    barra "Anota algo…" de Inicio. NO es conversación: el cerebro la
    guarda como apunte clasificado en una sola pasada.
    """

    texto: str = Field(min_length=1)


class CapturaApunteResponse(BaseModel):
    """Respuesta del endpoint `/matix/capturar-apunte`.

    Devuelve el apunte recién creado con su clasificación resuelta
    (Paso C): `proyecto_nombre` / `curso_nombre` cuando encajó en uno
    existente, o `general=True` si quedó suelto. La app arma con esto
    el snackbar de una línea ("Guardado en proyecto Tesis" / "Guardado
    como apunte general") y usa `id` para abrir/corregir el apunte.

    `tablas_cambiadas` siempre incluye `"apuntes"` para que la app
    invalide la lista de "Apuntes recientes" al instante.
    """

    id: str
    titulo: str
    etiquetas: list[str] = Field(default_factory=list)
    proyecto_nombre: str | None = None
    curso_nombre: str | None = None
    general: bool = True
    tablas_cambiadas: list[str] = Field(default_factory=lambda: ["apuntes"])


class ExtraerTareasRequest(BaseModel):
    """Cuerpo del endpoint `/matix/extraer-tareas` (Capa 7-B).

    `texto` es el resultado del OCR de una foto (Capa 7-A) que el
    usuario ya revisó y corrigió en la app. SOLO viaja el texto: la
    imagen se quedó en el teléfono. El cerebro lo lee y propone tareas;
    no crea nada — la app las muestra para que el usuario confirme.
    """

    texto: str = Field(min_length=1)


class TareaPropuesta(BaseModel):
    """Una tarea candidata extraída del texto.

    `vence_en` es una fecha (sin hora) o `None`. El modelo resuelve
    fechas relativas ('el viernes') a una fecha real; si la tarea no
    menciona fecha, queda en `None`. La app deja editar título y fecha
    en la hoja de revisión antes de crear.
    """

    titulo: str
    vence_en: date | None = None


class ExtraerTareasResponse(BaseModel):
    """Respuesta del endpoint `/matix/extraer-tareas`.

    `tareas` puede venir vacía cuando el texto no tiene acciones
    claras — es un resultado válido, no un error. La app lo muestra
    como "No encontré tareas claras en el texto".
    """

    tareas: list[TareaPropuesta] = Field(default_factory=list)


class TareaParaEstimar(BaseModel):
    """Una tarea que el planificador necesita dimensionar."""

    id: str
    titulo: str = Field(min_length=1)


class EstimarDuracionesRequest(BaseModel):
    """Cuerpo de `/matix/estimar-duraciones` (Urgencia-3).

    La app manda las tareas pendientes (id + título) que quiere
    planificar hoy; el cerebro estima cuántos minutos toma cada una.
    El encaje en los huecos del día lo hace la app de forma
    determinística — esto solo aporta la duración.
    """

    tareas: list[TareaParaEstimar] = Field(default_factory=list)


class DuracionEstimada(BaseModel):
    tarea_id: str
    minutos: int


class EstimarDuracionesResponse(BaseModel):
    """Respuesta de `/matix/estimar-duraciones`. Una entrada por tarea
    estimada; las que el modelo no pudo dimensionar se omiten y la app
    les aplica un default."""

    duraciones: list[DuracionEstimada] = Field(default_factory=list)


class DesglosarTareaRequest(BaseModel):
    """Cuerpo de `/matix/desglosar-tarea` (Capa 7 · Desglose).

    `titulo` es la tarea a partir; `nota` es contexto opcional. El
    cerebro propone pasos accionables; NO crea nada — la app los muestra
    para que el usuario revise y confirme.
    """

    titulo: str = Field(min_length=1)
    nota: str | None = None


class PasoPropuesto(BaseModel):
    """Un paso del desglose. `horizonte` ordena el paso en el tiempo:
    `ahora` (arrancar ya), `pronto`, `mas_adelante`."""

    titulo: str
    horizonte: Literal["ahora", "pronto", "mas_adelante"] = "pronto"


class DesglosarTareaResponse(BaseModel):
    """Respuesta de `/matix/desglosar-tarea`.

    Si la tarea ya es atómica, `es_atomica=True` y `pasos` viene vacía —
    la app muestra "esto ya es accionable, no hay qué desglosar".
    """

    es_atomica: bool = False
    pasos: list[PasoPropuesto] = Field(default_factory=list)


class ExtraerEventosRequest(BaseModel):
    """Cuerpo de `/matix/extraer-eventos` (Cámara · sílabo).

    `texto` es el OCR de un sílabo u horario (ya corregido por el
    usuario). SOLO viaja el texto: la imagen se quedó en el teléfono.
    El cerebro propone eventos; no crea nada.
    """

    texto: str = Field(min_length=1)


class EventoPropuesto(BaseModel):
    """Un evento candidato. `tipo` distingue clases recurrentes de
    fechas únicas. Para 'recurrente', `dias_semana` (ISO 1=lun…7=dom) y
    horas. Para 'unico', `fecha`. Las horas son HH:MM o null."""

    tipo: Literal["recurrente", "unico"]
    titulo: str
    dias_semana: list[int] = Field(default_factory=list)
    hora_inicio: str | None = None
    hora_fin: str | None = None
    fecha: date | None = None


class ExtraerEventosResponse(BaseModel):
    """Respuesta de `/matix/extraer-eventos`. `eventos` vacía cuando el
    texto no tiene nada datable — resultado válido, no error."""

    eventos: list[EventoPropuesto] = Field(default_factory=list)


class ChatResponse(BaseModel):
    """Respuesta del endpoint `/matix/chat`.

    `respuesta` es siempre texto natural para mostrar al usuario.

    `tools_usadas` y `tablas_cambiadas` son metadatos opcionales que
    aparecieron en Capa 2 Paso 2. La app los usa para decidir qué
    providers invalidar tras la respuesta — por ejemplo, si Matix
    creó una tarea, `tablas_cambiadas` incluirá `"tareas"` y el
    Notifier hará `ref.invalidate(tareasProvider)` para refrescar
    la lista al instante.
    """

    respuesta: str
    tools_usadas: list[str] = Field(default_factory=list)
    tablas_cambiadas: list[str] = Field(default_factory=list)
