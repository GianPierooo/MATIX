"""Sync de Google Calendar a Supabase (Capa 4 Paso 1).

Trae los eventos del calendario primario del usuario y los upserta
en `eventos` con `origen='google'` + `external_id` = id de Google.

Estrategia:

- Rango: desde hace 1 día hasta dentro de 90 días. Lo pasado lejano
  no nos interesa; el futuro lejano lo agarra el próximo sync.
- Eventos recurrentes: pedimos `singleEvents=True` para que Google
  nos los expanda. Cada instancia entra como evento separado en
  Supabase (más fácil de visualizar en la UI; al costo de varias
  filas por evento recurrente, pero el calendario del usuario no
  es tan denso como para que importe).
- UNIQUE constraint `(origen, external_id)` evita duplicar al
  re-sync: usamos upsert via PostgREST.
- Detección de borrado en Google: comparamos el set de IDs nuevos
  contra los que ya tenía Matix de esa cuenta; los que faltan se
  mandan a la papelera (soft-delete). Si en Google fue por error,
  el usuario los recupera desde la Papelera del hub.

NO tocamos eventos con `origen='manual'`. Esos son del usuario.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

from ..db import Postgrest
from . import oauth

logger = logging.getLogger("matix.google.calendar")

# Cuánto rango miramos en cada sync.
_VENTANA_ATRAS = timedelta(days=1)
_VENTANA_ADELANTE = timedelta(days=90)


async def sincronizar(
    db: Postgrest, email: str
) -> dict[str, int]:
    """Lee eventos del Calendar y los upserta a Supabase.

    Devuelve un dict con contadores: `creados`, `actualizados`,
    `mandados_a_papelera`, `total_remoto`. Útil para el endpoint
    `/google/sync` que la app llama y muestra al usuario.
    """
    creds = await oauth.obtener_credenciales(db, email)
    if creds is None:
        raise RuntimeError(
            f"No hay credenciales válidas para {email}. "
            "El usuario tiene que re-autorizar."
        )

    # `build` es síncrono (lib de Google no es async). Para una
    # request sola, no vale la pena pasarlo a un executor — corre
    # en milisegundos. Si en el futuro hacemos sync masivos en
    # background, lo movemos.
    servicio = build("calendar", "v3", credentials=creds, cache_discovery=False)

    ahora = datetime.now(timezone.utc)
    time_min = (ahora - _VENTANA_ATRAS).isoformat()
    time_max = (ahora + _VENTANA_ADELANTE).isoformat()

    eventos_remotos: list[dict] = []
    page_token: str | None = None
    while True:
        try:
            resp = (
                servicio.events()
                .list(
                    calendarId="primary",
                    timeMin=time_min,
                    timeMax=time_max,
                    singleEvents=True,
                    orderBy="startTime",
                    maxResults=250,
                    pageToken=page_token,
                )
                .execute()
            )
        except HttpError as e:
            raise RuntimeError(f"Google Calendar API: {e}") from e
        eventos_remotos.extend(resp.get("items", []))
        page_token = resp.get("nextPageToken")
        if not page_token:
            break

    # IDs que vimos en este sync (para detectar borrados).
    ids_remotos_actuales: set[str] = set()
    creados = 0
    actualizados = 0

    for ev in eventos_remotos:
        external_id = ev.get("id")
        if not external_id:
            continue
        # Eventos cancelados (Google los manda con status='cancelled'
        # incluso al expandir recurrencia) → los saltamos. El bloque
        # de "soft-delete por ausencia" los va a poner en papelera.
        if ev.get("status") == "cancelled":
            continue
        ids_remotos_actuales.add(external_id)
        fila = _evento_google_a_fila(ev, email)
        existia = await _existe(db, external_id, email)
        if existia:
            await _actualizar(db, external_id, email, fila)
            actualizados += 1
        else:
            await _insertar(db, fila)
            creados += 1

    # Soft-delete de eventos que estaban en Matix con origen google
    # y esta cuenta, pero ya no aparecen en Google. NO purgamos
    # permanentemente — van a papelera y el usuario los recupera si
    # fue un error.
    a_papelera = await _soft_delete_ausentes(
        db, email=email, ids_vivos=ids_remotos_actuales
    )

    await oauth.marcar_sync(db, email)

    return {
        "creados": creados,
        "actualizados": actualizados,
        "mandados_a_papelera": a_papelera,
        "total_remoto": len(eventos_remotos),
    }


# ─── helpers ────────────────────────────────────────────────────────


def _parse_google_dt(d: dict) -> tuple[str | None, bool]:
    """Acepta tanto `dateTime` (ISO con tz) como `date` (día entero).
    Devuelve `(iso_str, todo_el_dia)`."""
    if not d:
        return None, False
    if "dateTime" in d:
        return d["dateTime"], False
    if "date" in d:
        # Día entero: lo guardamos como medianoche UTC para que el
        # tipo timestamptz no se queje. La UI sabe que es todo_el_dia.
        return f"{d['date']}T00:00:00+00:00", True
    return None, False


def _evento_google_a_fila(ev: dict, email: str) -> dict:
    """Mapea un evento de Google a la forma que espera la tabla
    `eventos` de Supabase."""
    inicia, todo_dia_inicio = _parse_google_dt(ev.get("start") or {})
    termina, todo_dia_fin = _parse_google_dt(ev.get("end") or {})
    return {
        "titulo": (ev.get("summary") or "(sin título)").strip(),
        "descripcion": (ev.get("description") or "").strip() or None,
        "inicia_en": inicia,
        "termina_en": termina,
        "todo_el_dia": todo_dia_inicio or todo_dia_fin,
        "ubicacion": (ev.get("location") or "").strip() or None,
        "origen": "google",
        "external_id": ev["id"],
        "external_account": email,
    }


async def _existe(db: Postgrest, external_id: str, email: str) -> bool:
    filas = await db.list(
        "eventos",
        filters={"external_id": external_id, "external_account": email},
        limit=1,
    )
    return bool(filas)


async def _insertar(db: Postgrest, fila: dict) -> None:
    await db.insert("eventos", fila)


async def _actualizar(
    db: Postgrest, external_id: str, email: str, fila: dict
) -> None:
    """Actualiza el evento existente por (external_id, email).
    También limpia `eliminado_en` si estaba en papelera — si Google
    lo trae de nuevo, lo restauramos."""
    payload = {**fila, "eliminado_en": None}
    await db._http.patch(  # noqa: SLF001
        "/eventos",
        params={
            "external_id": f"eq.{external_id}",
            "external_account": f"eq.{email}",
        },
        json=payload,
    )


async def _soft_delete_ausentes(
    db: Postgrest, *, email: str, ids_vivos: set[str]
) -> int:
    """Marca con `eliminado_en` los eventos de la cuenta que ya no
    están en Google (excluyendo los que ya estaban en papelera).
    Devuelve cuántos se afectaron."""
    # Traemos todos los actuales de esta cuenta NO eliminados.
    actuales = await db.list(
        "eventos",
        filters={"origen": "google", "external_account": email},
        raw_filters={"eliminado_en": "is.null"},
    )
    desaparecidos = [
        a for a in actuales if a.get("external_id") not in ids_vivos
    ]
    if not desaparecidos:
        return 0
    ahora_iso = datetime.now(timezone.utc).isoformat()
    for d in desaparecidos:
        await db.update(
            "eventos", d["id"], {"eliminado_en": ahora_iso}
        )
    return len(desaparecidos)
