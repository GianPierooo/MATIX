"""Único punto de entrada al modelo de lenguaje.

**Ningún otro módulo del cerebro importa `openai`.** Esto es por
diseño: si en el futuro cambia el proveedor (Claude, Gemini, modelo
local), se reescribe este archivo y nada más. Los demás módulos
reciben `dict`s simples — incluso los tool calls se devuelven en
formato neutro para no acoplar `chat.py` a la SDK.

Decisión: OpenAI como único proveedor (2026-05-26). Modelo por
defecto `gpt-4o-mini` por costo bajo; se puede subir a `gpt-4o` para
mejor razonamiento. El **prompt caching** de OpenAI es automático
para prefijos repetidos ≥1024 tokens — basta con poner el system
prompt al inicio y mantenerlo estable.
"""
from __future__ import annotations

import json
from typing import Any

from openai import AsyncOpenAI

from ..config import settings
from .uso import medidor

_client: AsyncOpenAI | None = None


def _get_client() -> AsyncOpenAI:
    """Cliente lazy. Si la `OPENAI_API_KEY` no está, falla con
    mensaje claro en vez de un error confuso de la SDK."""
    global _client
    if _client is None:
        if not settings.openai_api_key:
            raise RuntimeError(
                "OPENAI_API_KEY no está configurada en cerebro/.env"
            )
        _client = AsyncOpenAI(api_key=settings.openai_api_key)
    return _client


async def responder(
    messages: list[dict],
    *,
    model: str = "gpt-4o-mini",
    temperature: float = 0.6,
) -> str:
    """Versión simple sin tools. Quedó como compat / debugging — el
    flujo real de Matix usa `responder_con_tools`."""
    client = _get_client()
    resp = await client.chat.completions.create(
        model=model,
        messages=messages,  # type: ignore[arg-type]
        temperature=temperature,
    )
    medidor.registrar_chat(resp.usage)
    return (resp.choices[0].message.content or "").strip()


async def responder_con_tools(
    messages: list[dict],
    tools: list[dict],
    *,
    model: str = "gpt-4o-mini",
    temperature: float = 0.6,
) -> dict[str, Any]:
    """Llama al modelo dándole acceso a `tools` (lista de schemas
    OpenAI). Devuelve un dict neutro que `chat.py` puede consumir sin
    importar `openai`:

        {
            "tipo": "texto",
            "contenido": "...",
            "raw": <mensaje original, opaco>
        }

    o bien:

        {
            "tipo": "tool_calls",
            "tool_calls": [
                {"id": "call_abc", "nombre": "crear_tarea", "args": {...}},
                ...
            ],
            "raw": <mensaje original, opaco>
        }

    El campo `raw` se vuelve a inyectar tal cual cuando se construye
    el siguiente turno (los modelos necesitan ver su propio mensaje
    con los `tool_call_id`s para enlazar las respuestas). Es opaco
    para `chat.py`.
    """
    client = _get_client()
    resp = await client.chat.completions.create(
        model=model,
        messages=messages,  # type: ignore[arg-type]
        temperature=temperature,
        tools=tools,  # type: ignore[arg-type]
        tool_choice="auto",
    )
    medidor.registrar_chat(resp.usage)
    msg = resp.choices[0].message

    if msg.tool_calls:
        calls = []
        for tc in msg.tool_calls:
            try:
                args = json.loads(tc.function.arguments or "{}")
            except json.JSONDecodeError:
                args = {}
            calls.append(
                {
                    "id": tc.id,
                    "nombre": tc.function.name,
                    "args": args,
                }
            )
        return {
            "tipo": "tool_calls",
            "tool_calls": calls,
            # El SDK acepta volver a pasarle el mensaje como dict.
            "raw": msg.model_dump(exclude_none=True),
        }

    return {
        "tipo": "texto",
        "contenido": (msg.content or "").strip(),
        "raw": msg.model_dump(exclude_none=True),
    }


async def transcribir(
    audio_bytes: bytes,
    *,
    nombre_archivo: str = "audio.m4a",
    mime: str = "audio/mp4",
    idioma: str = "es",
    model: str = "whisper-1",
) -> str:
    """Transcribe audio a texto vía Whisper.

    La app NUNCA habla con OpenAI directo — solo el cerebro. La app
    sube los bytes a `POST /api/v1/matix/transcribir` y el router
    llama a esta función.

    - `audio_bytes` debe ser un formato soportado por Whisper
      (m4a, mp3, wav, webm, ogg, flac…). En Android usamos m4a/AAC
      por defecto: compacto y nativo.
    - `idioma` ayuda a Whisper a no confundir el acento — fijamos
      `"es"` siempre (Gian Piero habla en español, y Whisper puede
      llegar a transcribir a inglés si el audio es corto).
    - Devuelve el texto crudo, sin recortar. Si el usuario habló
      poco y Whisper devuelve vacío, devolvemos string vacío y el
      caller decide qué hacer.
    """
    client = _get_client()
    # OpenAI SDK acepta `file=(filename, bytes, content_type)`.
    resp = await client.audio.transcriptions.create(
        model=model,
        file=(nombre_archivo, audio_bytes, mime),
        language=idioma,
    )
    # Whisper cobra por minuto de audio. Estimamos la duración usando
    # un ratio conservador: AAC mono 16 kHz ≈ 32 kbps = 4 KB/s.
    estimacion_seg = max(0.0, len(audio_bytes) / 4096.0)
    medidor.registrar_whisper(estimacion_seg)

    texto = (resp.text or "").strip()
    # Filtro de alucinaciones conocidas — Whisper tiende a inventar
    # estas frases cuando el audio es silencio o ruido sin habla.
    # Cuando vienen sueltas (sin más contenido), las descartamos.
    if _es_alucinacion_de_whisper(texto):
        return ""
    return texto


# Frases que Whisper inventa cuando el audio no tiene voz real.
# Vienen del corpus con el que se entrenó (subtítulos de YouTube,
# créditos de videos, etc.). Si la transcripción ES exactamente o
# CONTIENE solo una de estas (con poco más), la descartamos.
_ALUCINACIONES_WHISPER = (
    "subtítulos realizados por la comunidad de amara.org",
    "subtítulos por la comunidad de amara.org",
    "subtitulado por la comunidad de amara.org",
    "subtítulos por amara.org",
    "subtitles by the amara.org community",
    "subtítulos en español",
    "¡suscríbete!",
    "suscríbete al canal",
    "gracias por ver",
    "gracias por ver el video",
    "thanks for watching",
    "thank you for watching",
    "music",
    "[música]",
    "♪",
    "(música)",
    "transcrito por:",
)


async def hablar(
    texto: str,
    *,
    voz: str = "onyx",
    model: str = "tts-1",
    formato: str = "mp3",
) -> bytes:
    """Convierte `texto` a audio usando la TTS de OpenAI.

    Voz por defecto: `onyx` (masculina, grave, profesional). Otras
    voces disponibles: `alloy` (neutra), `echo` (masculina media),
    `fable` (británica), `nova` (femenina), `shimmer` (femenina).

    Modelo `tts-1` es el rápido (preferido para conversación en
    tiempo real); `tts-1-hd` cuesta el doble y suena un poco mejor.

    Devuelve los bytes del audio (mp3 por defecto). El caller los
    sirve al cliente como `audio/mpeg`. Registra el consumo en el
    medidor (cobra por caracteres del input).
    """
    client = _get_client()
    resp = await client.audio.speech.create(
        model=model,
        voice=voz,
        input=texto,
        response_format=formato,
    )
    medidor.registrar_tts(len(texto))
    # La SDK devuelve un HttpxBinaryResponseContent — .read() devuelve
    # los bytes completos.
    return await resp.aread()


def _es_alucinacion_de_whisper(texto: str) -> bool:
    """True si `texto` es una alucinación conocida de Whisper sobre
    silencio/ruido. Comparación case-insensitive y robusta a signos
    de puntuación al borde."""
    if not texto:
        return False
    normalizado = texto.lower().strip(" .!?¡¿\"'·-—\n\t")
    if not normalizado:
        return True  # solo signos/espacios
    if normalizado in _ALUCINACIONES_WHISPER:
        return True
    # Caso "Subtítulos … Amara.org. Subtítulos … Amara.org." (Whisper
    # repite la misma frase varias veces). Si todo el texto es una
    # repetición de una alucinación, también la descartamos.
    for hal in _ALUCINACIONES_WHISPER:
        if hal and hal in normalizado:
            sin_hal = normalizado.replace(hal, "").strip(" .,;:·-")
            if not sin_hal:
                return True
    return False
