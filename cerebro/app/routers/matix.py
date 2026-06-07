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

import logging
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from fastapi.responses import Response

from ..db import Postgrest, get_db
from ..matix import extraccion_documentos, idempotencia, llm, muestras_voz
from ..matix.chat import capturar_apunte, conversar
from ..matix.uso import medidor
from ..schemas.matix import (
    CapturaApunteRequest,
    CapturaApunteResponse,
    ChatRequest,
    ChatResponse,
    ClasificarCapturaRequest,
    ClasificarCapturaResponse,
    ConteoMuestrasResponse,
    DesglosarTareaRequest,
    DesglosarTareaResponse,
    DocumentoExtraidoResponse,
    EstimarDuracionesRequest,
    EstimarDuracionesResponse,
    ExtraerEventosRequest,
    ExtraerEventosResponse,
    ExtraerReciboRequest,
    ExtraerReciboResponse,
    ExtraerTareasRequest,
    ExtraerTareasResponse,
    MuestraVozResponse,
    NarrarFrameRequest,
    NarrarFrameResponse,
    TranscripcionResponse,
    VozRequest,
)
from ..security import require_api_key

logger = logging.getLogger("matix.routers.matix")

router = APIRouter(
    prefix="/matix",
    tags=["matix"],
    dependencies=[Depends(require_api_key)],
)

# Tope blando de tamaño para audio: 25 MB es el límite de Whisper.
# Lo recortamos antes para fallar rápido con un mensaje claro en
# vez de propagar un error opaco de OpenAI.
_MAX_AUDIO_BYTES = 24 * 1024 * 1024

# Mime por extensión de archivo de audio. La app sube m4a/AAC, pero el
# `Content-Type` del multipart a veces llega como `application/octet-stream`
# (el mapa de mimes del cliente no siempre conoce `.m4a`). Whisper puede
# rechazar un octet-stream genérico, así que inferimos un mime de audio
# correcto a partir de la extensión del nombre de archivo.
_MIME_POR_EXT = {
    "m4a": "audio/mp4",
    "mp4": "audio/mp4",
    "mp3": "audio/mpeg",
    "wav": "audio/wav",
    "webm": "audio/webm",
    "ogg": "audio/ogg",
    "oga": "audio/ogg",
    "flac": "audio/flac",
    "aac": "audio/aac",
    "mpga": "audio/mpeg",
    "mpeg": "audio/mpeg",
}


def _mime_audio(nombre: str, content_type: str | None) -> str:
    """Mime de audio fiable para mandar a Whisper.

    Prioriza la extensión del nombre (la app graba `.m4a`); si no la
    reconoce, usa el `content_type` del multipart salvo que sea el
    genérico `application/octet-stream`; en último caso, `audio/mp4`.
    """
    ext = nombre.rsplit(".", 1)[-1].lower() if "." in nombre else ""
    if ext in _MIME_POR_EXT:
        return _MIME_POR_EXT[ext]
    if content_type and content_type != "application/octet-stream":
        return content_type
    return "audio/mp4"


# Tope blando de la imagen del chat (data URL base64). ~5 MB de imagen
# ≈ 6.7M chars; dejamos margen. La app además comprime antes de mandar.
_MAX_IMAGEN_CHARS = 7_000_000

# Tope de imágenes por mensaje (debe coincidir con el del cliente y el de
# `chat._MAX_IMAGENES`): varias ayudan, pero cada una infla tokens.
_MAX_IMAGENES_CHAT = 5


@router.post("/chat", response_model=ChatResponse)
async def chat(body: ChatRequest, db: Postgrest = Depends(get_db)) -> dict:
    # Imágenes del turno: `imagen` (singular, compat) + `imagenes` (varias).
    todas = list(body.imagenes or [])
    if body.imagen:
        todas.insert(0, body.imagen)
    if len(todas) > _MAX_IMAGENES_CHAT:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Demasiadas imágenes: máximo {_MAX_IMAGENES_CHAT} por mensaje.",
        )
    for img in todas:
        if not img.startswith("data:image/"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cada imagen debe venir como data URL (data:image/…).",
            )
        if len(img) > _MAX_IMAGEN_CHARS:
            raise HTTPException(
                status_code=413,  # Content Too Large
                detail="Una imagen es muy pesada. Adjunta una más liviana.",
            )
    async def _correr() -> dict:
        return await conversar(
            db,
            historial=[m.model_dump() for m in body.historial],
            mensaje=body.mensaje,
            imagenes=todas,
            documento=body.documento.model_dump() if body.documento else None,
        )

    # Idempotencia + reconciliación: con `idempotency_key`, un reintento tras
    # una caída devuelve el resultado guardado sin re-ejecutar (no duplica). Sin
    # clave, corre como siempre.
    key = (body.idempotency_key or "").strip()
    try:
        if key:
            resultado = await idempotencia.ejecutar_idempotente(db, key, _correr)
        else:
            resultado = await _correr()
    except idempotencia.EnProceso as e:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Esa operación sigue en proceso; reintenta en un momento.",
        ) from e
    except RuntimeError as e:
        # Caso típico: OPENAI_API_KEY no configurada.
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(e),
        ) from e
    except Exception as e:  # noqa: BLE001
        # Logueamos con detalle (incluido el body del 400 del proveedor) para
        # diagnosticar. Un 400 de request inválido NO es un 502: lo reportamos
        # como 400 para no esconderlo tras un "error del cerebro" genérico.
        code = getattr(e, "status_code", None)
        logger.exception("chat: fallo llamando al modelo (status=%s)", code)
        if code == 400:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Petición inválida al modelo: {e}",
            ) from e
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


@router.post("/extraer-recibo", response_model=ExtraerReciboResponse)
async def extraer_recibo(body: ExtraerReciboRequest) -> dict:
    """Convierte el texto de un recibo/boleta (OCR ya corregido) en un
    gasto propuesto: monto, fecha, comercio y categoría sugerida
    (Finanzas-2). SOLO viaja el texto: la imagen se quedó en el teléfono.
    No persiste nada — la app lo revisa y lo guarda en Finanzas. Si no hay
    un total claro, `monto` viene null y la app lo deja escribir a mano
    (no se inventan cifras)."""
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
        recibo = await llm.extraer_recibo_json(texto, hoy=hoy)
    except RuntimeError as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(e)
        ) from e
    except Exception as e:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Error llamando al modelo: {e}",
        ) from e
    return {"recibo": recibo}


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
    mime = _mime_audio(nombre, file.content_type)

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


# Tope del documento: 10 MB. Un PDF/DOCX típico de apuntes o un sílabo está
# muy por debajo; cortamos antes para fallar claro y no procesar archivos
# enormes (la extracción ya capea el TEXTO a ~16k chars aparte).
_MAX_DOCUMENTO_BYTES = 10 * 1024 * 1024


@router.post("/extraer-documento", response_model=DocumentoExtraidoResponse)
async def extraer_documento(
    file: UploadFile = File(..., description="Documento (PDF/DOCX/TXT/MD)."),
) -> dict:
    """Recibe un documento y devuelve su TEXTO extraído.

    La app lo sube por multipart cuando el usuario adjunta un documento en el
    chat. Reusa la misma extracción que la ingestión de material
    (`extraccion_documentos`). No persiste nada: el texto vuelve a la app, que
    lo manda como `documento` en el siguiente turno del chat para que Matix lo
    lea/analice/resuma (y puede ofrecer guardarlo en apuntes).
    """
    datos = await file.read()
    if not datos:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El documento está vacío.",
        )
    if len(datos) > _MAX_DOCUMENTO_BYTES:
        raise HTTPException(
            status_code=413,  # Content Too Large
            detail="El documento supera el tope de 10 MB. Adjunta uno más liviano.",
        )

    nombre = file.filename or "documento"
    try:
        texto, truncado = extraccion_documentos.extraer(nombre, datos)
    except extraccion_documentos.DocumentoNoSoportado as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail=str(e)
        ) from e
    except RuntimeError as e:
        # Falta pypdf / python-docx en el server.
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(e)
        ) from e
    except Exception as e:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"No pude leer el documento: {e}",
        ) from e

    if not texto:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=(
                "El documento no tiene texto legible (¿es un PDF escaneado? "
                "Prueba con la cámara para OCR)."
            ),
        )

    return {
        "nombre": nombre,
        "texto": texto,
        "caracteres": len(texto),
        "truncado": truncado,
    }


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
        audio, proveedor = await llm.hablar(texto, voz=body.voz)
    except RuntimeError as e:
        # Todo el TTS cloud cayó → 503. La app cae a la voz del dispositivo.
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(e),
        ) from e
    except Exception as e:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"TTS falló: {e}",
        ) from e

    return Response(
        content=audio,
        media_type="audio/mpeg",
        headers={
            "Cache-Control": "no-store",
            "Content-Length": str(len(audio)),
            # Observabilidad: qué proveedor de voz sirvió este audio.
            "X-TTS-Proveedor": proveedor,
        },
    )


@router.post("/narrar-frame", response_model=NarrarFrameResponse)
async def narrar_frame(body: NarrarFrameRequest) -> dict:
    """Cámara EN VIVO: narra en una frase corta un frame muestreado por la app.

    El MUESTREO y los TOPES (intervalo, frames/min, auto-corte) los hace la app:
    acá solo llegan los frames que pasaron el filtro, así el costo se controla
    en origen. La imagen viaja como data URL y NO se persiste. Devuelve narración
    vacía si no hay nada nuevo (gpt-4o-mini con visión en `detail=low`, barato)."""
    img = (body.imagen or "").strip()
    if not img.startswith("data:image/"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Falta `imagen` como data URL (data:image/...).",
        )
    if len(img) > 8_000_000:  # ~6 MB de imagen; tope defensivo
        raise HTTPException(status_code=413, detail="La imagen es demasiado grande.")
    try:
        narracion = await llm.narrar_frame(
            img, narracion_previa=body.narracion_previa
        )
    except RuntimeError as e:
        # Config (sin API key): la cámara no puede narrar. Honesto y raro.
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(e)
        ) from e
    except Exception:  # noqa: BLE001
        # La visión falló tras reintentos (502/timeout pasajero). DEGRADAMOS a
        # narración vacía (200) en vez de 502: la cámara NUNCA debe morir por un
        # frame; este se salta y el siguiente lo intenta de nuevo.
        logger.warning("narrar-frame: visión falló tras reintentos; narro vacío")
        return {"narracion": ""}
    return {"narracion": narracion}


# ---------------------------------------------------------------------------
# Wake word personalizado — muestras de voz del usuario.
#
# La app graba clips ("oye matix" = positivo; otras frases = negativo) y los
# sube uno a uno. Los guardamos en un bucket PRIVADO de Supabase Storage con la
# service_role (server-side). Luego se bajan en un .zip para reentrenar el
# modelo "oye matix" afinado a la voz real del usuario.
# ---------------------------------------------------------------------------


@router.post("/wakeword/muestras", response_model=MuestraVozResponse)
async def subir_muestra_voz(
    tipo: str = Form(..., description="positivo | negativo"),
    indice: int = Form(..., description="Índice del clip dentro de su tipo."),
    file: UploadFile = File(..., description="Clip WAV 16 kHz mono."),
) -> dict:
    """Recibe un clip de voz y lo guarda en Storage (upsert por tipo+índice)."""
    if tipo not in muestras_voz.TIPOS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"tipo inválido (usa {' | '.join(muestras_voz.TIPOS)}).",
        )
    if indice < 0 or indice > 999:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="índice fuera de rango (0..999).",
        )
    datos = await file.read()
    if not datos:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="El clip está vacío."
        )
    if len(datos) > muestras_voz.MAX_CLIP_BYTES:
        raise HTTPException(
            status_code=413, detail="El clip supera el tope de 2 MB."
        )
    try:
        objeto = await muestras_voz.subir(tipo, indice, datos)
        c = await muestras_voz.conteo()
    except muestras_voz.StorageNoConfigurado as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(e)
        ) from e
    except Exception as e:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"No pude guardar el clip: {e}",
        ) from e
    return {"ok": True, "objeto": objeto, "conteo": c}


@router.get("/wakeword/muestras/conteo", response_model=ConteoMuestrasResponse)
async def conteo_muestras_voz() -> dict:
    """Cuántos clips hay guardados (positivos / negativos / total)."""
    try:
        return await muestras_voz.conteo()
    except muestras_voz.StorageNoConfigurado as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(e)
        ) from e
    except Exception as e:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY, detail=str(e)
        ) from e


@router.delete("/wakeword/muestras", response_model=ConteoMuestrasResponse)
async def borrar_muestras_voz() -> dict:
    """Vacía el bucket para empezar una grabación desde cero."""
    try:
        await muestras_voz.borrar_todos()
        return await muestras_voz.conteo()
    except muestras_voz.StorageNoConfigurado as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(e)
        ) from e
    except Exception as e:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY, detail=str(e)
        ) from e


@router.get("/wakeword/muestras.zip")
async def descargar_muestras_voz_zip() -> Response:
    """Devuelve TODAS las muestras en un .zip (carpetas positivo/ y negativo/).

    Lo bajo a la PC con la clave para alimentar el reentrenamiento en Colab.
    """
    try:
        datos = await muestras_voz.zip_todos()
    except muestras_voz.StorageNoConfigurado as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(e)
        ) from e
    except Exception as e:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"No pude armar el zip: {e}",
        ) from e
    return Response(
        content=datos,
        media_type="application/zip",
        headers={
            "Content-Disposition": "attachment; filename=oye_matix_muestras.zip",
            "Content-Length": str(len(datos)),
        },
    )
