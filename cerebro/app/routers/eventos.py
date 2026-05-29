"""CRUD de `eventos` con borrado suave (Capa 2 Paso 5) + sync
bidireccional con Google Calendar (Capa 4 Paso 2).

Ver `routers/tareas.py` para el modelo de borrado suave: DELETE
manda a papelera, `/restaurar` recupera, `/permanente` destruye.

Bidireccional con Google
========================

Después de cada CRUD intentamos propagar al Calendar del usuario,
con dos políticas distintas según el origen del evento:

- **Manual** (`origen='manual'`, creados desde Matix):
  *hub primero, Google después, best-effort*. Si Google rebota,
  el evento queda local y el próximo `/google/sync` lo backfilea.
  El cliente nunca ve un error por Google — su dato siempre se
  guardó.

- **Google** (`origen='google'`, importados):
  *Google primero, hub solo si Google acepta*. Si Google rebota
  (403 porque el usuario no es organizador, 410 si ya fue borrado,
  etc.), respondemos al cliente con ese error y NO aplicamos en
  el hub. Evita desync donde el hub diría "editado" y Google no.

Detalle en `docs/Plan_Capa4.md` · Quién puede editar qué.
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from googleapiclient.errors import HttpError

from ..db import Postgrest, get_db
from ..google import calendar as gcal
from ..google import oauth as goauth
from ..schemas.eventos import EventoCreate, EventoRead, EventoUpdate
from ..security import require_api_key

logger = logging.getLogger("matix.eventos")

router = APIRouter(
    prefix="/eventos",
    tags=["eventos"],
    dependencies=[Depends(require_api_key)],
)

TABLE = "eventos"


def _ahora_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


async def _email_google_si_hay(db: Postgrest) -> str | None:
    """Devuelve el email de la cuenta Google conectada, o None si
    no hay conexión activa. Lo usamos para decidir si intentar push.
    """
    cuenta = await goauth.cuenta_conectada(db)
    if cuenta is None:
        return None
    if not cuenta.get("tiene_escritura"):
        # Conectado con scope readonly del Paso 1 — no podemos
        # pushear. El usuario tiene que reconectar.
        return None
    return cuenta["email"]


def _http_status_de_google(e: HttpError) -> int:
    """Mapea un HttpError de Google a un status HTTP nuestro.
    No reusamos el status raw porque algunos (401, 5xx) los
    queremos como 502 para que la app sepa que es upstream."""
    s = e.resp.status
    if s == 403:
        return status.HTTP_403_FORBIDDEN
    if s == 404 or s == 410:
        return status.HTTP_404_NOT_FOUND
    if 400 <= s < 500:
        return status.HTTP_400_BAD_REQUEST
    return status.HTTP_502_BAD_GATEWAY


@router.get("", response_model=list[EventoRead])
async def listar(
    papelera: bool = Query(default=False),
    db: Postgrest = Depends(get_db),
) -> list[dict]:
    raw_filters = {
        "eliminado_en": "not.is.null" if papelera else "is.null",
    }
    return await db.list(
        TABLE, order="inicia_en.asc", raw_filters=raw_filters
    )


@router.get("/{evento_id}", response_model=EventoRead)
async def obtener(evento_id: UUID, db: Postgrest = Depends(get_db)) -> dict:
    row = await db.get(TABLE, str(evento_id))
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Evento no encontrado"
        )
    return row


@router.post("", response_model=EventoRead, status_code=status.HTTP_201_CREATED)
async def crear(body: EventoCreate, db: Postgrest = Depends(get_db)) -> dict:
    """Crea un evento manual y, si hay Google conectado, lo empuja
    al Calendar del usuario. Manual = hub primero, push best-effort.
    """
    row = await db.insert(
        TABLE, body.model_dump(mode="json", exclude_none=True)
    )
    email = await _email_google_si_hay(db)
    if email is None:
        return row
    try:
        patch = await gcal.push_evento(
            db, email=email, fila=row, accion="crear"
        )
    except (HttpError, RuntimeError) as e:
        logger.warning(
            "Push a Google falló para evento %s — queda local "
            "hasta el próximo sync: %s",
            row["id"],
            e,
        )
        return row
    return await db.update(TABLE, row["id"], patch)


@router.patch("/{evento_id}", response_model=EventoRead)
async def actualizar(
    evento_id: UUID, body: EventoUpdate, db: Postgrest = Depends(get_db)
) -> dict:
    actual = await db.get(TABLE, str(evento_id))
    if actual is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Evento no encontrado"
        )
    payload = body.model_dump(mode="json", exclude_unset=True)
    # La fila proyectada (la que iría a Google) combina el estado
    # actual con el patch — Google espera el objeto completo, no
    # solo el delta.
    fila_proyectada = {**actual, **payload}

    email = await _email_google_si_hay(db)
    tiene_external = bool(actual.get("external_id"))
    accion_google = "editar" if tiene_external else "crear"

    # Para `origen='google'`: empujar a Google PRIMERO. Si rebota,
    # no aplicamos al hub.
    if actual.get("origen") == "google" and email and tiene_external:
        try:
            patch_google = await gcal.push_evento(
                db,
                email=email,
                fila=fila_proyectada,
                accion="editar",
            )
        except HttpError as e:
            raise HTTPException(
                status_code=_http_status_de_google(e),
                detail=f"Google rechazó la edición: {e}",
            ) from e
        payload = {**payload, **patch_google}
        row = await db.update(TABLE, str(evento_id), payload)
        return row

    # Para `origen='manual'`: hub primero, Google después best-effort.
    row = await db.update(TABLE, str(evento_id), payload)
    if email is None:
        return row
    try:
        patch_google = await gcal.push_evento(
            db,
            email=email,
            fila={**row, **payload},
            accion=accion_google,
        )
    except (HttpError, RuntimeError) as e:
        logger.warning(
            "Push a Google falló al editar evento %s — queda local: %s",
            row["id"],
            e,
        )
        return row
    if patch_google:
        row = await db.update(TABLE, str(evento_id), patch_google)
    return row


@router.delete("/{evento_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar(evento_id: UUID, db: Postgrest = Depends(get_db)) -> None:
    """Borrado suave. Si el evento estaba sincronizado con Google,
    también lo borra allá (best-effort para manuales; obligatorio
    para google = si Google rebota, no aplicamos el soft-delete)."""
    actual = await db.get(TABLE, str(evento_id))
    if actual is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Evento no encontrado"
        )

    email = await _email_google_si_hay(db)
    tiene_external = bool(actual.get("external_id"))

    # `origen='google'`: borrar en Google primero. Si rebota,
    # no aplicamos.
    if actual.get("origen") == "google" and email and tiene_external:
        try:
            await gcal.push_evento(
                db, email=email, fila=actual, accion="borrar"
            )
        except HttpError as e:
            raise HTTPException(
                status_code=_http_status_de_google(e),
                detail=f"Google rechazó el borrado: {e}",
            ) from e

    # `origen='manual'`: borrar en Google best-effort y siempre
    # soft-delete local.
    if actual.get("origen") == "manual" and email and tiene_external:
        try:
            await gcal.push_evento(
                db, email=email, fila=actual, accion="borrar"
            )
        except (HttpError, RuntimeError) as e:
            logger.warning(
                "Push delete a Google falló para evento %s — sigo "
                "con soft-delete local: %s",
                actual["id"],
                e,
            )

    row = await db.update(
        TABLE, str(evento_id), {"eliminado_en": _ahora_iso()}
    )
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Evento no encontrado"
        )


@router.post("/{evento_id}/restaurar", response_model=EventoRead)
async def restaurar(
    evento_id: UUID, db: Postgrest = Depends(get_db)
) -> dict:
    """Saca de papelera. Para los eventos con external_id, dispara
    un push 'crear' a Google porque allá ya no existe (lo borramos
    cuando se mandó a papelera). Google asigna un nuevo ID; lo
    guardamos."""
    actual = await db.get(TABLE, str(evento_id))
    if actual is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Evento no encontrado"
        )

    # Limpiamos external_id viejo (el evento de Google ya fue borrado)
    # y volvemos a empujar si hay conexión.
    payload: dict[str, Any] = {
        "eliminado_en": None,
        "external_id": None,
        "external_account": None,
        "google_updated_at": None,
    }
    row = await db.update(TABLE, str(evento_id), payload)

    email = await _email_google_si_hay(db)
    if email is None:
        return row
    try:
        patch_google = await gcal.push_evento(
            db, email=email, fila=row, accion="crear"
        )
    except (HttpError, RuntimeError) as e:
        logger.warning(
            "Push tras restaurar evento %s falló — queda local: %s",
            row["id"],
            e,
        )
        return row
    return await db.update(TABLE, str(evento_id), patch_google)


@router.delete(
    "/{evento_id}/permanente", status_code=status.HTTP_204_NO_CONTENT
)
async def eliminar_permanente(
    evento_id: UUID, db: Postgrest = Depends(get_db)
) -> None:
    """Borrado físico — NO toca Google (asumimos que ya se borró
    allá cuando el evento fue a papelera). Si por algún motivo
    seguía en Google, el próximo pull lo va a re-importar."""
    ok = await db.delete(TABLE, str(evento_id))
    if not ok:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Evento no encontrado"
        )
