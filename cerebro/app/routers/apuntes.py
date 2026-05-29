"""CRUD de `apuntes` con borrado suave (Capa 2 Paso 5).

Ver `routers/tareas.py` para el modelo conceptual: DELETE manda al
papelera, `/restaurar` lo recupera, `/permanente` destruye.
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any
from uuid import UUID

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    File,
    Form,
    HTTPException,
    Query,
    UploadFile,
    status,
)

from ..db import Postgrest, get_db
from ..matix.indexador import indexar_apunte
from ..schemas.apuntes import (
    ApunteCreate,
    ApunteDesdeFoto,
    ApunteRead,
    ApunteUpdate,
)
from ..security import require_api_key
from ..vision import ocr as vision_ocr
from ..vision import storage as vision_storage

logger = logging.getLogger("matix.apuntes")

router = APIRouter(
    prefix="/apuntes",
    tags=["apuntes"],
    dependencies=[Depends(require_api_key)],
)

TABLE = "apuntes"


def _ahora_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


@router.get("", response_model=list[ApunteRead])
async def listar(
    papelera: bool = Query(default=False),
    db: Postgrest = Depends(get_db),
) -> list[dict]:
    raw_filters = {
        "eliminado_en": "not.is.null" if papelera else "is.null",
    }
    return await db.list(
        TABLE, order="actualizado_en.desc", raw_filters=raw_filters
    )


@router.get("/{apunte_id}", response_model=ApunteRead)
async def obtener(apunte_id: UUID, db: Postgrest = Depends(get_db)) -> dict:
    row = await db.get(TABLE, str(apunte_id))
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Apunte no encontrado"
        )
    return row


async def _reindexar_silencioso(db: Postgrest, apunte: dict) -> None:
    """Wrapper que indexa el apunte en background y NO propaga
    excepciones — el usuario ya recibió el 200/201, no queremos
    abortarlo si OpenAI está caído o algo falla. El próximo edit
    del apunte (o el script de backfill) lo reintenta."""
    try:
        await indexar_apunte(db, apunte)
    except Exception:  # noqa: BLE001
        logger.exception(
            "indexador falló para apunte %s", apunte.get("id")
        )


@router.post("", response_model=ApunteRead, status_code=status.HTTP_201_CREATED)
async def crear(
    body: ApunteCreate,
    bg: BackgroundTasks,
    db: Postgrest = Depends(get_db),
) -> dict:
    creado = await db.insert(TABLE, body.model_dump(mode="json", exclude_none=True))
    # Indexar en background: la llamada a OpenAI tarda ~1s; no
    # queremos bloquear el response.
    bg.add_task(_reindexar_silencioso, db, creado)
    return creado


def _titulo_por_defecto() -> str:
    """Si la app no manda título, uno con fecha+hora local del
    cerebro alcanza para que el apunte sea identificable en la
    lista. El usuario lo edita después."""
    ahora = datetime.now(timezone.utc).astimezone()
    return f"Apunte del {ahora.strftime('%d/%m %H:%M')}"


def _csv_a_etiquetas(crudo: str | None) -> list[str]:
    if not crudo:
        return []
    return [e.strip() for e in crudo.split(",") if e.strip()]


@router.post(
    "/desde-foto",
    response_model=ApunteDesdeFoto,
    status_code=status.HTTP_201_CREATED,
)
async def crear_desde_foto(
    bg: BackgroundTasks,
    file: UploadFile = File(...),
    titulo: str | None = Form(default=None),
    curso_id: str | None = Form(default=None),
    proyecto_id: str | None = Form(default=None),
    cuaderno_id: str | None = Form(default=None),
    etiquetas: str | None = Form(default=None),
    db: Postgrest = Depends(get_db),
) -> dict[str, Any]:
    """Foto → apunte (Capa 7 · Paso 1).

    1. Sube la imagen al bucket `apuntes-img` con nombre uuid.
    2. Llama a OpenAI vision sobre la URL pública.
    3. Crea el apunte con el texto extraído + la imagen adjunta.
    4. Dispara el auto-embed para RAG en background como cualquier
       otro apunte.

    Si OCR falla, el apunte SE CREA igual con `contenido=""` y la
    foto adjunta. La respuesta lleva `ocr_ok=false` + un mensaje
    legible para que la UI lo muestre como warning, no como error.
    """
    # 1) Subir la imagen primero. Si esto falla, sí abortamos —
    # sin la foto no hay nada que guardar.
    contenido_imagen = await file.read()
    try:
        adjunto = await vision_storage.subir_imagen_apunte(
            contenido_imagen,
            content_type=file.content_type,
            nombre_original=file.filename,
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail=str(e)
        ) from e
    except RuntimeError as e:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY, detail=str(e)
        ) from e

    # 2) OCR. Falla aislada — no aborta la creación del apunte.
    ocr_ok = True
    mensaje_ocr: str | None = None
    texto = ""
    try:
        texto = await vision_ocr.extraer_texto(url_imagen=adjunto["url"])
        if not texto:
            ocr_ok = False
            mensaje_ocr = (
                "No detecté texto legible en la imagen. "
                "Podés editarla a mano."
            )
    except Exception as e:  # noqa: BLE001
        logger.warning("OCR vision falló: %s", e)
        ocr_ok = False
        mensaje_ocr = (
            "No pude leer el texto en este momento. La foto quedó "
            "adjunta; editá el contenido a mano."
        )

    # 3) Construir el ApunteCreate y persistir por el mismo camino
    # que la creación normal — así el auto-embed dispara solo.
    body = ApunteCreate(
        titulo=(titulo or "").strip() or _titulo_por_defecto(),
        contenido=texto,
        curso_id=UUID(curso_id) if curso_id else None,
        proyecto_id=UUID(proyecto_id) if proyecto_id else None,
        cuaderno_id=UUID(cuaderno_id) if cuaderno_id else None,
        etiquetas=_csv_a_etiquetas(etiquetas),
        adjuntos=[adjunto],
    )
    creado = await db.insert(
        TABLE, body.model_dump(mode="json", exclude_none=True)
    )
    bg.add_task(_reindexar_silencioso, db, creado)

    return {**creado, "ocr_ok": ocr_ok, "mensaje_ocr": mensaje_ocr}


@router.patch("/{apunte_id}", response_model=ApunteRead)
async def actualizar(
    apunte_id: UUID,
    body: ApunteUpdate,
    bg: BackgroundTasks,
    db: Postgrest = Depends(get_db),
) -> dict:
    payload = body.model_dump(mode="json", exclude_unset=True)
    row = await db.update(TABLE, str(apunte_id), payload)
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Apunte no encontrado"
        )
    # Re-indexar si cambió contenido relevante para búsqueda.
    if any(k in payload for k in ("titulo", "contenido", "etiquetas")):
        bg.add_task(_reindexar_silencioso, db, row)
    return row


@router.delete("/{apunte_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar(apunte_id: UUID, db: Postgrest = Depends(get_db)) -> None:
    """Borrado suave."""
    row = await db.update(
        TABLE, str(apunte_id), {"eliminado_en": _ahora_iso()}
    )
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Apunte no encontrado"
        )


@router.post("/{apunte_id}/restaurar", response_model=ApunteRead)
async def restaurar(
    apunte_id: UUID, db: Postgrest = Depends(get_db)
) -> dict:
    row = await db.update(TABLE, str(apunte_id), {"eliminado_en": None})
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Apunte no encontrado"
        )
    return row


@router.delete(
    "/{apunte_id}/permanente", status_code=status.HTTP_204_NO_CONTENT
)
async def eliminar_permanente(
    apunte_id: UUID, db: Postgrest = Depends(get_db)
) -> None:
    ok = await db.delete(TABLE, str(apunte_id))
    if not ok:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Apunte no encontrado"
        )
