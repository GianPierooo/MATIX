from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class MensajeChat(BaseModel):
    """Un mensaje del historial. `rol` es `user` o `assistant`."""

    rol: Literal["user", "assistant"]
    contenido: str


class ChatRequest(BaseModel):
    """Cuerpo del endpoint `/matix/chat`."""

    historial: list[MensajeChat] = Field(default_factory=list)
    mensaje: str = Field(min_length=1)


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
