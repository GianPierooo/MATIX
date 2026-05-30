"""Router del chat y la voz con Matix.

Endpoints:

- `POST /matix/chat` — turno de conversación (Capa 2 Paso 1 + 2).
  El cerebro arma el system prompt, llama a OpenAI con tools, y
  devuelve la respuesta narrada + metadatos para invalidar la UI.

- `POST /matix/transcribir` — audio → texto vía Whisper (Capa 2
  Paso 3). Solo entrada por voz: el texto va al campo del composer
  para que Gian Piero lo revise y mande él. No se ejecuta acción
  ninguna desde aquí.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from fastapi.responses import Response

from ..db import Postgrest, get_db
from ..matix import llm
from ..matix.chat import capturar_apunte, conversar
from ..matix.uso import medidor
from ..schemas.matix import (
    CapturaApunteRequest,
    CapturaApunteResponse,
    ChatRequest,
    ChatResponse,
    ClasificarCapturaRequest,
    ClasificarCapturaResponse,
    DesglosarTareaRequest,
    DesglosarTareaResponse,
    EstimarDuracionesRequest,
    EstimarDuracionesResponse,
    ExtraerEventosRequest,
    ExtraerEventosResponse,
    ExtraerTareasRequest,
    ExtraerTareasResponse,
    TranscripcionResponse,
    VozRequest,
)
from ..security import require_api_key

router = APIRouter(
    prefix="/matix",
    tags=["matix"],
    dependencies=[Depends(require_api_key)],
)

# Tope blando de tamaño para audio: 25 MB es el límite de Whisper.
# Lo recortamos antes para fallar rápido con un mensaje claro en
# vez de propagar un error opaco de OpenAI.
_MAX_AUDIO_BYTES = 24 * 1024 * 1024


# Tope blando de la imagen del chat (data URL base64). ~5 MB de imagen
# ≈ 6.7M chars; dejamos margen. La app además comprime antes de mandar.
_MAX_IMAGEN_CHARS = 7_000_000


@router.post("/chat", response_model=ChatResponse)
async def chat(body: ChatRequest, db: Postgrest = Depends(get_db)) -> dict:
    imagen = body.imagen
    if imagen is not None:
        if not imagen.startswith("data:image/"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="La imagen debe venir como data URL (data:image/…).",
            )
        if len(imagen) > _MAX_IMAGEN_CHARS:
            raise HTTPException(
                status_code=413,  # Content Too Large
                detail="La imagen es muy pesada. Adjunta una más liviana.",
            )
    try:
        resultado = await conversar(
            db,
            historial=[m.model_dump() for m in body.historial],
            mensaje=body.mensaje,
            imagen=imagen,
        )
    except RuntimeError as e:
        # Caso típico: OPENAI_API_KEY no configurada.
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(e),
        ) from e
    except Exception as e:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Error llamando al modelo: {e}",
        ) from e
    return resultado


@router.post("/capturar-apunte", response_model=CapturaApunteResponse)
async def capturar(
    body: CapturaApunteRequest, db: Postgrest = Depends(get_db)
) -> dict:
    """Captura rápida desde Inicio: guarda `texto` como apunte ya
    clasificado (Paso C2). NO abre conversación ni narra — fuerza
    `crear_apunte` una sola vez y devuelve dónde quedó archivado.

    La app llama a esto tras transcribir la voz con Whisper. Con la
    respuesta arma el snackbar de una línea y permite abrir/corregir
    el apunte recién creado.
    """
    try:
        resultado = await capturar_apunte(db, texto=body.texto)
    except RuntimeError as e:
        # OPENAI_API_KEY ausente, o el modelo no generó la captura.
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(e),
        ) from e
    except Exception as e:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Error llamando al modelo: {e}",
        ) from e

    if not resultado.get("ok"):
        # La tool falló (validación, BD…). No dejamos un apunte
        # huérfano: devolvemos el error para que la app lo muestre.
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=resultado.get("mensaje", "No se pudo guardar el apunte."),
        )

    datos = resultado["datos"]
    return {
        "id": str(datos["id"]),
        "titulo": datos["titulo"],
        "etiquetas": datos.get("etiquetas", []),
        "proyecto_nombre": datos.get("proyecto_nombre"),
        "curso_nombre": datos.get("curso_nombre"),
        "general": datos.get("general", True),
        "tablas_cambiadas": ["apuntes"],
    }


@router.post("/extraer-tareas", response_model=ExtraerTareasResponse)
async def extraer_tareas(body: ExtraerTareasRequest) -> dict:
    """Convierte texto libre (OCR de una foto, ya corregido por el
    usuario) en tareas estructuradas que la app muestra para revisar
    (Capa 7-B).

    SOLO viaja el texto: la imagen se quedó en el teléfono (Capa 7-A).
    Este endpoint **no persiste nada** — devuelve las tareas propuestas
    y la app las crea con su CRUD de siempre tras la confirmación del
    usuario. Si el texto no tiene tareas claras, `tareas` viene vacía.
    """
    texto = body.texto.strip()
    if not texto:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El texto está vacío.",
        )

    # La fecha de referencia es HOY en Lima (UTC-5, sin DST). El cerebro
    # corre con reloj UTC; explicitamos la conversión para que "el
    # viernes" se resuelva contra el día del usuario, no el del server.
    hoy = (
        datetime.now(timezone.utc)
        .astimezone(timezone(timedelta(hours=-5)))
        .strftime("%Y-%m-%d")
    )

    try:
        tareas = await llm.extraer_tareas_json(texto, hoy=hoy)
    except RuntimeError as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(e),
        ) from e
    except Exception as e:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Error llamando al modelo: {e}",
        ) from e

    return {"tareas": tareas}


@router.post("/extraer-eventos", response_model=ExtraerEventosResponse)
async def extraer_eventos(body: ExtraerEventosRequest) -> dict:
    """Convierte el texto de un sílabo u horario (OCR ya corregido) en
    eventos propuestos: clases recurrentes y fechas únicas (Cámara ·
    sílabo). SOLO viaja el texto. No persiste nada — la app los revisa y
    crea. Si no hay nada datable, `eventos` viene vacía."""
    texto = body.texto.strip()
    if not texto:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El texto está vacío.",
        )
    hoy = (
        datetime.now(timezone.utc)
        .astimezone(timezone(timedelta(hours=-5)))
        .strftime("%Y-%m-%d")
    )
    try:
        eventos = await llm.extraer_eventos_json(texto, hoy=hoy)
    except RuntimeError as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(e)
        ) from e
    except Exception as e:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Error llamando al modelo: {e}",
        ) from e
    return {"eventos": eventos}


@router.post("/clasificar-captura", response_model=ClasificarCapturaResponse)
async def clasificar_captura(body: ClasificarCapturaRequest) -> dict:
    """Mira el texto de una captura (OCR on-device de una foto) y dice a
    cuál de los tres flujos de la cámara inteligente pertenece: `tareas`,
    `eventos` o `apunte`. SOLO viaja el texto: la imagen se quedó en el
    teléfono. No persiste nada — la app abre la revisión del flujo
    sugerido y el usuario puede corregir el tipo. Ante duda, devuelve
    `apunte` (catch-all)."""
    texto = body.texto.strip()
    if not texto:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El texto está vacío.",
        )
    try:
        tipo = await llm.clasificar_captura_json(texto)
    except RuntimeError as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(e)
        ) from e
    except Exception as e:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Error llamando al modelo: {e}",
        ) from e
    return {"tipo": tipo}


@router.post("/estimar-duraciones", response_model=EstimarDuracionesResponse)
async def estimar_duraciones(body: EstimarDuracionesRequest) -> dict:
    """Estima la duración (minutos) de cada tarea para planificar el día
    (Urgencia-3). No persiste nada ni encaja bloques — solo dimensiona.
    La app arma el plan determinístico con estas duraciones.

    Si no hay tareas, devuelve lista vacía sin llamar al modelo. Si el
    modelo falla, propaga el error para que la app aplique su default y
    siga (nunca se queda muda)."""
    tareas = [{"id": t.id, "titulo": t.titulo} for t in body.tareas]
    if not tareas:
        return {"duraciones": []}

    try:
        duraciones = await llm.estimar_duraciones_json(tareas)
    except RuntimeError as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(e),
        ) from e
    except Exception as e:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Error llamando al modelo: {e}",
        ) from e

    return {
        "duraciones": [
            {"tarea_id": tid, "minutos": m} for tid, m in duraciones.items()
        ]
    }


@router.post("/desglosar-tarea", response_model=DesglosarTareaResponse)
async def desglosar_tarea(body: DesglosarTareaRequest) -> dict:
    """Parte una tarea en pasos accionables con horizonte (Capa 7 ·
    Desglose). No persiste nada — la app revisa y crea los pasos. Si la
    tarea ya es atómica, devuelve `es_atomica=True` y `pasos=[]`."""
    try:
        resultado = await llm.desglosar_tarea_json(
            body.titulo, contexto=body.nota
        )
    except RuntimeError as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(e),
        ) from e
    except Exception as e:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Error llamando al modelo: {e}",
        ) from e
    return resultado


@router.post("/transcribir", response_model=TranscripcionResponse)
async def transcribir(
    file: UploadFile = File(..., description="Audio del usuario."),
) -> dict:
    """Recibe un audio y devuelve la transcripción en español.

    La app sube los bytes vía multipart/form-data en el campo `file`.
    Aceptamos cualquier formato soportado por Whisper; en la app por
    defecto grabamos m4a/AAC (compacto y nativo en Android).

    Esta ruta **no** ejecuta acciones sobre el hub ni invoca al
    modelo de chat — solo devuelve el texto. La razón es de
    seguridad: queremos que Gian Piero vea lo que Whisper escuchó
    antes de mandárselo a Matix con todas sus tools detrás.
    """
    audio = await file.read()
    if not audio:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El audio está vacío.",
        )
    if len(audio) > _MAX_AUDIO_BYTES:
        raise HTTPException(
            status_code=413,  # Content Too Large
            detail=(
                "El audio supera el tope de 24 MB. Grabá un fragmento "
                "más corto."
            ),
        )

    nombre = file.filename or "audio.m4a"
    mime = file.content_type or "audio/mp4"

    try:
        texto = await llm.transcribir(
            audio, nombre_archivo=nombre, mime=mime
        )
    except RuntimeError as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(e),
        ) from e
    except Exception as e:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Whisper falló al transcribir: {e}",
        ) from e

    return {"texto": texto}


@router.get("/uso")
async def uso_acumulado() -> dict:
    """Devuelve el medidor de uso acumulado de OpenAI desde que se
    arrancó este proceso del cerebro: tokens (input/output/cached),
    minutos de Whisper, y costo estimado en USD. La franja del chat
    en la app lo polea cada N segundos."""
    return medidor.snapshot()


@router.post("/voz")
async def voz(body: VozRequest) -> Response:
    """Text-to-speech: recibe `{texto, voz?}` y devuelve audio mp3.

    Decisión Capa 2 Paso 5.1: usamos la TTS de OpenAI con voz `onyx`
    (masculina grave) en vez de `flutter_tts` del dispositivo. Razones:

    - El motor TTS del teléfono Huawei del usuario solo expone voces
      femeninas en es-ES y suenan robóticas.
    - OpenAI `tts-1` con `onyx` da una voz masculina natural,
      consistente entre dispositivos y con latencia <1s para frases
      cortas.
    - Costo: $15 por 1M chars; una respuesta típica de Matix son
      ~200 chars → $0.003. Despreciable para uso personal.
    - Ya proxeamos a OpenAI para chat y Whisper; la API key queda
      en el cerebro como pediste.
    """
    texto = body.texto.strip()
    if not texto:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El texto está vacío.",
        )
    if len(texto) > 4000:
        # tts-1 acepta hasta ~4096 chars de input. Cortamos antes
        # con un mensaje claro.
        raise HTTPException(
            status_code=413,
            detail="El texto es demasiado largo para una sola lectura.",
        )
    try:
        audio = await llm.hablar(texto, voz=body.voz)
    except RuntimeError as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(e),
        ) from e
    except Exception as e:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"TTS de OpenAI falló: {e}",
        ) from e

    return Response(
        content=audio,
        media_type="audio/mpeg",
        headers={
            "Cache-Control": "no-store",
            "Content-Length": str(len(audio)),
        },
    )
