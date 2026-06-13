"""CRUD de `apuntes` con borrado suave (Capa 2 Paso 5).

Ver `routers/tareas.py` para el modelo conceptual: DELETE manda al
papelera, `/restaurar` lo recupera, `/permanente` destruye.
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone
from uuid import UUID

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    HTTPException,
    Query,
    status,
)

from ..db import Postgrest, get_db
from ..matix import recuerdos
from ..matix.indexador import indexar_apunte
from ..schemas.apuntes import (
    ApunteCreate,
    ApunteRead,
    ApunteUpdate,
)
from ..security import require_api_key

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
    del apunte (o el script de backfill) lo reintenta.

    Indexa en DOS tiendas: `apunte_chunks` (búsqueda explícita por la tool
    `buscar_apuntes`) Y la memoria UNIFICADA `recuerdos` (recall automático del
    chat). Ambas best-effort."""
    try:
        await indexar_apunte(db, apunte)
    except Exception:  # noqa: BLE001
        logger.exception(
            "indexador falló para apunte %s", apunte.get("id")
        )
    try:
        await recuerdos.indexar_entidad(db, "nota", apunte)
    except Exception:  # noqa: BLE001
        logger.exception("recuerdos falló para apunte %s", apunte.get("id"))


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
    # En la papelera → fuera del recall (Matix no recuerda lo borrado).
    recuerdos.olvidar_entidad_async(db, "nota", str(apunte_id))


@router.post("/{apunte_id}/restaurar", response_model=ApunteRead)
async def restaurar(
    apunte_id: UUID, db: Postgrest = Depends(get_db)
) -> dict:
    row = await db.update(TABLE, str(apunte_id), {"eliminado_en": None})
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Apunte no encontrado"
        )
    # Vuelve del limbo → re-indexar a memoria.
    recuerdos.indexar_entidad_async(db, "nota", row)
    return row


@router.post("/{apunte_id}/archivar", response_model=ApunteRead)
async def archivar(apunte_id: UUID, db: Postgrest = Depends(get_db)) -> dict:
    """Reflote (Capa 7): archiva el apunte para que NO vuelva a
    reflotarse en Inicio. No lo borra ni lo manda a la papelera — sigue
    en la lista de Apuntes; solo deja de ser candidato a reflote."""
    row = await db.update(TABLE, str(apunte_id), {"archivado_en": _ahora_iso()})
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Apunte no encontrado"
        )
    return row


@router.post("/{apunte_id}/retomar", response_model=ApunteRead)
async def retomar(apunte_id: UUID, db: Postgrest = Depends(get_db)) -> dict:
    """Reflote (Capa 7): marca el apunte como tocado para que salga del
    reflote (vuelve a dormirse y reflotará otra vez tras ~14 días sin
    actividad). 'Tocar' = cualquier update: el trigger
    `tocar_actualizado` pone `actualizado_en = now()`, que es la marca de
    'última vez tocada' que usa el reflote."""
    row = await db.update(TABLE, str(apunte_id), {"actualizado_en": _ahora_iso()})
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
    recuerdos.olvidar_entidad_async(db, "nota", str(apunte_id))
