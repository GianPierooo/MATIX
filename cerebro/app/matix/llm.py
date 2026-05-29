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
    tool_choice: Any = "auto",
) -> dict[str, Any]:
    """Llama al modelo dándole acceso a `tools` (lista de schemas
    OpenAI). Devuelve un dict neutro que `chat.py` puede consumir sin
    importar `openai`:

    `tool_choice` por defecto `"auto"` (el modelo decide). Para forzar
    una herramienta concreta se pasa
    `{"type": "function", "function": {"name": "crear_apunte"}}` —
    así la captura rápida de Inicio garantiza que el modelo guarde el
    apunte en vez de ponerse a conversar.

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
        tool_choice=tool_choice,  # type: ignore[arg-type]
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


async def extraer_tareas_json(
    texto: str,
    *,
    hoy: str,
    model: str = "gpt-4o-mini",
) -> list[dict]:
    """Extrae tareas accionables de un texto libre y las devuelve
    estructuradas (Capa 7-B). El texto suele venir del OCR de una foto
    (una lista escrita a mano, una pizarra, un post-it) ya corregido
    por el usuario, así que puede traer ruido y errores.

    Usa el **modo JSON** de OpenAI (`response_format=json_object`):
    el modelo está obligado a responder un objeto JSON válido, así no
    tenemos que rascar texto libre buscando el bloque.

    Devuelve una lista de dicts `{"titulo": str, "vence_en": str|None}`
    donde `vence_en` es una fecha `YYYY-MM-DD` o `None`. Reglas que
    fija el prompt:

    - Solo acciones concretas que la persona debe HACER. Prosa,
      definiciones, apuntes de estudio o ruido → no son tareas.
    - Si el texto no tiene tareas claras, devuelve lista vacía. NO
      inventa tareas ni fechas.
    - Resuelve fechas relativas ("el viernes", "mañana", "en dos
      semanas") a una fecha real usando `hoy` como referencia. Si una
      tarea no menciona fecha, `vence_en` es `null`.

    `hoy` se pasa como `YYYY-MM-DD` en hora de Lima (lo calcula el
    router). Esto mantiene la función pura y testeable: misma entrada,
    misma salida, sin depender del reloj del proceso.
    """
    client = _get_client()
    system = (
        "Eres un extractor de tareas. Recibes un texto libre que puede "
        "venir del escaneo (OCR) de una foto: una lista escrita a mano, "
        "una pizarra, notas sueltas. Puede traer errores de OCR.\n\n"
        f"Hoy es {hoy} (zona horaria de Lima, Perú).\n\n"
        "Tu trabajo: identificar las ACCIONES CONCRETAS que la persona "
        "debe hacer y devolverlas como JSON. Reglas estrictas:\n"
        "- Solo tareas accionables (algo que se hace y se completa). La "
        "prosa, las definiciones, los apuntes de estudio o el ruido NO "
        "son tareas.\n"
        "- Si el texto no contiene tareas claras, devuelve la lista "
        "vacía. NO inventes tareas.\n"
        "- Cada tarea: un título corto y claro en infinitivo o imperativo "
        "('Comprar pan', 'Entregar informe').\n"
        "- Si la tarea menciona una fecha (relativa o absoluta), "
        "resuélvela a una fecha real en formato YYYY-MM-DD usando la "
        "fecha de hoy como referencia. Si no menciona fecha, usa null. "
        "NO inventes fechas.\n\n"
        'Responde SOLO un objeto JSON con esta forma exacta:\n'
        '{"tareas": [{"titulo": "...", "vence_en": "YYYY-MM-DD" | null}]}'
    )
    resp = await client.chat.completions.create(
        model=model,
        messages=[
            {"role": "system", "content": system},
            {"role": "user", "content": texto},
        ],
        temperature=0.2,
        response_format={"type": "json_object"},
    )
    medidor.registrar_chat(resp.usage)

    contenido = resp.choices[0].message.content or "{}"
    try:
        datos = json.loads(contenido)
    except json.JSONDecodeError:
        return []

    crudas = datos.get("tareas") if isinstance(datos, dict) else None
    if not isinstance(crudas, list):
        return []

    tareas: list[dict] = []
    for item in crudas:
        if not isinstance(item, dict):
            continue
        titulo = item.get("titulo")
        if not isinstance(titulo, str) or not titulo.strip():
            continue
        vence = item.get("vence_en")
        if not isinstance(vence, str) or not vence.strip():
            vence = None
        tareas.append({"titulo": titulo.strip(), "vence_en": vence})
    return tareas


async def estimar_duraciones_json(
    tareas: list[dict],
    *,
    model: str = "gpt-4o-mini",
) -> dict[str, int]:
    """Estima cuántos minutos toma cada tarea, por su título (Urgencia-3).

    Se usa al planificar el día: el planificador necesita una duración
    por tarea para encajarla en los huecos reales. Si la app no la
    tiene, Matix la estima acá.

    `tareas` es una lista de dicts `{"id": str, "titulo": str}`. Devuelve
    un dict `{tarea_id: minutos}` con un entero de minutos por tarea
    (múltiplos de 15, entre 15 y 180). El que NO se pueda estimar se
    omite — el caller aplica un default razonable. Función pura respecto
    al reloj: misma entrada, misma salida (mockeable en tests).
    """
    items = [
        {"id": str(t["id"]), "titulo": str(t["titulo"]).strip()}
        for t in tareas
        if t.get("id") and str(t.get("titulo", "")).strip()
    ]
    if not items:
        return {}

    client = _get_client()
    system = (
        "Eres un planificador. Recibes una lista de tareas (id + título) "
        "y estimas cuánto tiempo de trabajo enfocado toma cada una.\n\n"
        "Reglas:\n"
        "- Devuelve minutos como entero, múltiplo de 15, entre 15 y 180.\n"
        "- Sé realista: una tarea breve ('responder correo') ~15-30 min; "
        "una mediana ('redactar resumen') ~45-60; uno grande ('estudiar "
        "para el examen') ~90-120.\n"
        "- Estima por el título nomás; no inventes contexto.\n\n"
        'Responde SOLO un objeto JSON con esta forma exacta:\n'
        '{"duraciones": [{"tarea_id": "...", "minutos": 45}]}'
    )
    user = json.dumps({"tareas": items}, ensure_ascii=False)
    resp = await client.chat.completions.create(
        model=model,
        messages=[
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        temperature=0.2,
        response_format={"type": "json_object"},
    )
    medidor.registrar_chat(resp.usage)

    contenido = resp.choices[0].message.content or "{}"
    try:
        datos = json.loads(contenido)
    except json.JSONDecodeError:
        return {}
    crudas = datos.get("duraciones") if isinstance(datos, dict) else None
    if not isinstance(crudas, list):
        return {}

    out: dict[str, int] = {}
    for item in crudas:
        if not isinstance(item, dict):
            continue
        tid = item.get("tarea_id")
        minutos = item.get("minutos")
        if not isinstance(tid, str) or not isinstance(minutos, int):
            continue
        # Acota al rango razonable y redondea a múltiplos de 15.
        m = max(15, min(180, minutos))
        m = round(m / 15) * 15
        out[tid] = m
    return out


_HORIZONTES = {"ahora", "pronto", "mas_adelante"}


async def desglosar_tarea_json(
    titulo: str,
    *,
    contexto: str | None = None,
    model: str = "gpt-4o-mini",
) -> dict:
    """Parte una tarea en pasos accionables, en orden lógico, cada uno
    etiquetado por horizonte (Capa 7 · Desglose).

    Devuelve un dict:
        {"es_atomica": bool, "pasos": [{"titulo": str, "horizonte": str}]}

    `horizonte` es uno de `"ahora"`, `"pronto"`, `"mas_adelante"`.

    Honestidad: si la tarea YA es un paso concreto y atómico, el modelo
    devuelve `es_atomica=True` y `pasos=[]` — no infla pasos de relleno.
    """
    client = _get_client()
    system = (
        "Eres un asistente que parte tareas en pasos accionables. "
        "Recibes el título de una tarea (y a veces una nota con "
        "contexto) y la desglosas en pasos CONCRETOS, en orden lógico.\n\n"
        "Reglas estrictas:\n"
        "- Cada paso es una acción concreta que se hace y se completa "
        "(empieza con un verbo). Nada de pasos vagos ni de relleno.\n"
        "- Si la tarea YA es atómica y accionable (no hay nada que "
        "desglosar), devuelve es_atomica=true y pasos=[]. NO inventes "
        "pasos para justificar el desglose.\n"
        "- Etiqueta cada paso por horizonte temporal: 'ahora' (lo "
        "primero, lo que se puede arrancar ya), 'pronto' (el siguiente "
        "tramo), 'mas_adelante' (lo que viene después). Ordena los pasos "
        "de 'ahora' a 'mas_adelante'.\n"
        "- Entre 2 y 8 pasos; títulos cortos.\n\n"
        "Responde SOLO un objeto JSON con esta forma exacta:\n"
        '{"es_atomica": false, "pasos": [{"titulo": "...", '
        '"horizonte": "ahora" | "pronto" | "mas_adelante"}]}'
    )
    user = titulo.strip()
    if contexto and contexto.strip():
        user += f"\n\nContexto: {contexto.strip()}"

    resp = await client.chat.completions.create(
        model=model,
        messages=[
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        temperature=0.3,
        response_format={"type": "json_object"},
    )
    medidor.registrar_chat(resp.usage)

    contenido = resp.choices[0].message.content or "{}"
    try:
        datos = json.loads(contenido)
    except json.JSONDecodeError:
        return {"es_atomica": False, "pasos": []}
    if not isinstance(datos, dict):
        return {"es_atomica": False, "pasos": []}

    es_atomica = bool(datos.get("es_atomica", False))
    crudas = datos.get("pasos")
    pasos: list[dict] = []
    if isinstance(crudas, list):
        for item in crudas:
            if not isinstance(item, dict):
                continue
            t = item.get("titulo")
            if not isinstance(t, str) or not t.strip():
                continue
            h = item.get("horizonte")
            if h not in _HORIZONTES:
                h = "pronto"
            pasos.append({"titulo": t.strip(), "horizonte": h})

    # Si no hay pasos, lo tratamos como atómica (no hay nada que crear).
    if not pasos:
        es_atomica = True
    return {"es_atomica": es_atomica, "pasos": pasos}


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


async def embebir(
    textos: list[str],
    *,
    model: str = "text-embedding-3-small",
) -> list[list[float]]:
    """Convierte una lista de textos en vectores (1536 dims con
    `text-embedding-3-small`). Sigue siendo el único punto del
    cerebro que importa `openai` — esto es Capa 3 Paso 1 RAG.

    Hace una sola llamada para toda la lista (batching), que es
    mucho más barato que una llamada por texto. Registra el uso
    sumando todos los tokens del batch.

    No deduplica ni cachea: el caller decide qué textos pasar.
    Para apuntes, el caller embebe título+contenido juntos.
    """
    if not textos:
        return []
    client = _get_client()
    resp = await client.embeddings.create(model=model, input=textos)
    medidor.registrar_embedding(resp.usage.total_tokens)
    # OpenAI devuelve los embeddings en el mismo orden del input.
    return [item.embedding for item in resp.data]


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
