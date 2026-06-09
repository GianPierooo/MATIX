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

from ..comandos import registro
from ..comandos.http import datos_o_http as _datos_o_http
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
    """Crea un evento por el comando `crear_evento` (misma ruta que la IA y el
    OCR de sílabo) y, si hay Google conectado, lo empuja best-effort. Manual =
    hub primero, push best-effort."""
    res = await registro.ejecutar(
        db, "crear_evento", body.model_dump(mode="json", exclude_none=True), origen="ui"
    )
    row = _datos_o_http(res)
    email = await _email_google_si_hay(db)
    if email is None:
        return row
    try:
        patch = await gcal.push_evento(db, email=email, fila=row, accion="crear")
    except (HttpError, RuntimeError) as e:
        logger.warning(
            "Push a Google falló para evento %s — queda local hasta el próximo "
            "sync: %s", row["id"], e,
        )
        return row
    return await db.update(TABLE, row["id"], patch)


@router.patch("/{evento_id}", response_model=EventoRead)
async def actualizar(
    evento_id: UUID,
    body: EventoUpdate,
    db: Postgrest = Depends(get_db),
    alcance: str = Query(default="toda_serie"),
    ocurrencia_fecha: str | None = Query(default=None),
) -> dict:
    """Edita un evento por el comando `editar_evento`. `alcance` controla los
    eventos recurrentes: toda_serie (default) / solo_esta / esta_y_futuras
    (con `ocurrencia_fecha` YYYY-MM-DD para las dos últimas)."""
    actual = await db.get(TABLE, str(evento_id))
    if actual is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Evento no encontrado"
        )
    edits = body.model_dump(mode="json", exclude_unset=True)
    params: dict[str, Any] = {**edits, "evento_id": str(evento_id), "alcance": alcance}
    if ocurrencia_fecha:
        params["ocurrencia_fecha"] = ocurrencia_fecha

    email = await _email_google_si_hay(db)
    tiene_external = bool(actual.get("external_id"))
    es_serie_entera = alcance == "toda_serie"

    # `origen='google'` + serie entera: empujar a Google PRIMERO; si rebota, no
    # tocamos el hub (el comando ni se llama).
    if actual.get("origen") == "google" and email and tiene_external and es_serie_entera:
        try:
            patch_google = await gcal.push_evento(
                db, email=email, fila={**actual, **edits}, accion="editar"
            )
        except HttpError as e:
            raise HTTPException(
                status_code=_http_status_de_google(e),
                detail=f"Google rechazó la edición: {e}",
            ) from e
        row = _datos_o_http(await registro.ejecutar(db, "editar_evento", params, origen="ui"))
        if patch_google:
            row = await db.update(TABLE, str(evento_id), patch_google)
        return row

    # Resto (manual, o sin external, o alcance que parte la serie): hub por el
    # comando primero.
    row = _datos_o_http(await registro.ejecutar(db, "editar_evento", params, origen="ui"))
    # Sin push inmediato a Google si se partió la serie: las filas nuevas
    # sincronizan en el próximo ciclo (igual que cualquier evento manual nuevo).
    if email is None or not es_serie_entera:
        return row
    accion_google = "editar" if tiene_external else "crear"
    try:
        patch_google = await gcal.push_evento(
            db, email=email, fila=row, accion=accion_google
        )
    except (HttpError, RuntimeError) as e:
        logger.warning(
            "Push a Google falló al editar evento %s — queda local: %s", row["id"], e,
        )
        return row
    if patch_google:
        row = await db.update(TABLE, str(evento_id), patch_google)
    return row


@router.delete("/{evento_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar(
    evento_id: UUID,
    db: Postgrest = Depends(get_db),
    alcance: str = Query(default="toda_serie"),
    ocurrencia_fecha: str | None = Query(default=None),
) -> None:
    """Borrado suave por el comando `eliminar_evento`. `alcance`: toda_serie
    (default, manda la serie a papelera y borra en Google si aplica) /
    solo_esta / esta_y_futuras (tocan la regla; no sincronizan a Google)."""
    actual = await db.get(TABLE, str(evento_id))
    if actual is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Evento no encontrado"
        )

    email = await _email_google_si_hay(db)
    tiene_external = bool(actual.get("external_id"))
    es_serie_entera = alcance == "toda_serie"

    # Borrado en Google solo cuando se borra la serie ENTERA (es lo único que
    # quita el evento de allá). Detachar/cortar la recurrencia no se sincroniza.
    if es_serie_entera and email and tiene_external:
        if actual.get("origen") == "google":
            try:
                await gcal.push_evento(db, email=email, fila=actual, accion="borrar")
            except HttpError as e:
                raise HTTPException(
                    status_code=_http_status_de_google(e),
                    detail=f"Google rechazó el borrado: {e}",
                ) from e
        else:  # manual: best-effort
            try:
                await gcal.push_evento(db, email=email, fila=actual, accion="borrar")
            except (HttpError, RuntimeError) as e:
                logger.warning(
                    "Push delete a Google falló para evento %s — sigo con "
                    "soft-delete local: %s", actual["id"], e,
                )

    params: dict[str, Any] = {"evento_id": str(evento_id), "alcance": alcance}
    if ocurrencia_fecha:
        params["ocurrencia_fecha"] = ocurrencia_fecha
    res = await registro.ejecutar(db, "eliminar_evento", params, origen="ui")
    _datos_o_http(res)  # levanta el status que toque si hubo error; 204 si ok


@router.post("/{evento_id}/restaurar", response_model=EventoRead)
async def restaurar(
    evento_id: UUID, db: Postgrest = Depends(get_db)
) -> dict:
    """Saca de papelera por el comando `restaurar_evento`. Para los eventos con
    external_id, dispara un push 'crear' a Google porque allá ya no existe."""
    res = await registro.ejecutar(
        db, "restaurar_evento", {"evento_id": str(evento_id)}, origen="ui"
    )
    row = _datos_o_http(res)

    email = await _email_google_si_hay(db)
    if email is None:
        return row
    try:
        patch_google = await gcal.push_evento(db, email=email, fila=row, accion="crear")
    except (HttpError, RuntimeError) as e:
        logger.warning(
            "Push tras restaurar evento %s falló — queda local: %s", row["id"], e,
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
