"""Sync de Google Calendar (Capa 4 Pasos 1 y 2).

Maneja las dos direcciones del calendario:

- **Pull** (`sincronizar`): trae eventos de Google y los upserta a
  Supabase con `origen='google'` + `external_id` = id de Google.
  Detecta borrados en Google y manda los faltantes a la papelera
  del hub (soft-delete). Aplica **last-write-wins** por timestamp:
  si el hub tiene una versión más reciente, skipea ese evento.
- **Push** (`push_evento`): empuja cambios del hub al Calendar.
  Soporta crear / editar / borrar. Para los `origen='manual'`
  sin `external_id` queda implícito el insert; para los que ya
  fueron empujados antes, update por id.
- **Backfill** (`_empujar_pendientes`): antes de cada pull, barre
  los eventos manuales del hub sin `external_id` y los empuja.
  Cubre el caso "usé Matix antes de conectar Google" y "Google
  estaba caído al crear este evento".

Loop prevention:

- UNIQUE `(external_account, external_id)` en `eventos` evita
  duplicar al volver del pull tras un push. El próximo pull
  encuentra el evento por ese par y lo trata como existente —
  el `origen` no cambia.
- Last-write-wins por `google_updated_at` vs `actualizado_en` con
  epsilon de 2s evita que el pull pise una edición local recién
  hecha. Detalle en `docs/Plan_Capa4.md` · Conflictos.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Any

from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

from ..db import Postgrest
from . import oauth

logger = logging.getLogger("matix.google.calendar")

# Cuánto rango miramos en cada sync.
_VENTANA_ATRAS = timedelta(days=1)
_VENTANA_ADELANTE = timedelta(days=90)

# Tolerancia para comparar timestamps Supabase vs Google. Cubre drift
# de relojes y lag de red. Si Google reporta `updated` más nuevo que
# `hub.actualizado_en` por menos de esto, consideramos que es el mismo
# estado y no aplicamos al hub (probablemente fue eco de un push nuestro).
_EPSILON_CONFLICTO = timedelta(seconds=2)


def _servicio_calendar(creds: Any) -> Any:
    """Construye el cliente síncrono de Calendar v3 con `cache_discovery=False`
    (sino tira advertencias por intentar escribir en `~/.cache/google` que
    no siempre existe en contenedores)."""
    return build("calendar", "v3", credentials=creds, cache_discovery=False)


def _evento_hub_a_body_google(fila: dict[str, Any]) -> dict[str, Any]:
    """Mapea una fila del hub al body que espera Google Calendar API.

    Diseñado para crear y para `patch` (Google ignora claves vacías o
    cuyo cambio no aplique).
    """
    body: dict[str, Any] = {
        "summary": fila["titulo"],
    }
    if fila.get("descripcion"):
        body["description"] = fila["descripcion"]
    if fila.get("ubicacion"):
        body["location"] = fila["ubicacion"]

    inicia_en = fila["inicia_en"]
    termina_en = fila.get("termina_en") or inicia_en

    if fila.get("todo_el_dia"):
        # Google exige date-only para all-day. Cortamos el ISO en T.
        body["start"] = {"date": str(inicia_en)[:10]}
        body["end"] = {"date": str(termina_en)[:10]}
    else:
        body["start"] = {"dateTime": str(inicia_en)}
        body["end"] = {"dateTime": str(termina_en)}
    return body


async def push_evento(
    db: Postgrest,
    *,
    email: str,
    fila: dict[str, Any],
    accion: str,
) -> dict[str, Any]:
    """Propaga un cambio del hub al Calendar del usuario.

    `accion` ∈ {'crear', 'editar', 'borrar'}.

    - `crear`: insert en Google → guarda `external_id`,
      `external_account` y `google_updated_at` en la fila del hub.
      Asume que la fila ya tiene `id` (Supabase) y que `external_id`
      es NULL o se va a sobreescribir.
    - `editar`: PATCH en Google sobre el `external_id` de la fila →
      refresca `google_updated_at`.
    - `borrar`: DELETE en Google sobre el `external_id`. NO toca
      la fila del hub (el caller decide cómo registrar el borrado:
      soft-delete o permanente).

    Devuelve un dict con las claves que el caller debería persistir
    en la fila del hub (`external_id`, `external_account`,
    `google_updated_at`) para `crear` y `editar`. Para `borrar`,
    devuelve `{}`.

    Lanza:
    - `RuntimeError` si no hay credenciales válidas.
    - `HttpError` de Google si el push fracasa (403, 404, 410, etc.).
      El caller decide qué hacer con el error según el flujo
      (manual → loggear y seguir; google → propagar al cliente).
    """
    creds = await oauth.obtener_credenciales(db, email)
    if creds is None:
        raise RuntimeError(
            f"No hay credenciales válidas para {email}. "
            "El usuario tiene que re-autorizar."
        )
    servicio = _servicio_calendar(creds)

    if accion == "crear":
        body = _evento_hub_a_body_google(fila)
        resp = servicio.events().insert(
            calendarId="primary", body=body
        ).execute()
        return {
            "external_id": resp["id"],
            "external_account": email,
            "google_updated_at": resp.get("updated"),
        }

    if accion == "editar":
        external_id = fila.get("external_id")
        if not external_id:
            raise RuntimeError(
                "No puedo editar en Google sin external_id; "
                "tiene que pasar primero por 'crear'."
            )
        body = _evento_hub_a_body_google(fila)
        resp = servicio.events().patch(
            calendarId="primary", eventId=external_id, body=body
        ).execute()
        return {"google_updated_at": resp.get("updated")}

    if accion == "borrar":
        external_id = fila.get("external_id")
        if not external_id:
            # Nunca se pusheó → no hay nada que borrar en Google.
            return {}
        try:
            servicio.events().delete(
                calendarId="primary", eventId=external_id
            ).execute()
        except HttpError as e:
            # 404/410: ya no estaba en Google. No es error desde
            # nuestra perspectiva — el estado final coincide.
            if e.resp.status in (404, 410):
                logger.info(
                    "Evento %s ya no estaba en Google al borrar (%s).",
                    external_id,
                    e.resp.status,
                )
                return {}
            raise
        return {}

    raise ValueError(f"acción desconocida: {accion!r}")


async def sincronizar(
    db: Postgrest, email: str
) -> dict[str, int]:
    """Sync bidireccional con el Calendar del usuario.

    Orden de operaciones:

    1. **Backfill**: push de eventos manuales del hub que aún no
       tienen `external_id`. Cubre el caso "creé eventos antes de
       conectar Google" o "Google estaba caído al guardar".
    2. **Pull**: trae los eventos de Google y los upserta a
       Supabase. Aplica last-write-wins: si el hub tiene una
       versión más reciente (porque el usuario acaba de editar
       local), se skipea.
    3. **Soft-delete por ausencia**: eventos `origen='google'`
       que ya no están en Google → van a papelera.

    Devuelve contadores para que la UI muestre el resumen.
    """
    creds = await oauth.obtener_credenciales(db, email)
    if creds is None:
        raise RuntimeError(
            f"No hay credenciales válidas para {email}. "
            "El usuario tiene que re-autorizar."
        )

    # 1) Backfill — empujar eventos manuales pendientes ANTES del pull.
    # Hacerlo antes garantiza que cuando Google nos los devuelva en
    # el pull, ya tienen `external_id` y los reconocemos como
    # existentes en vez de duplicar.
    empujados = await _empujar_pendientes(db, email=email)

    # `build` es síncrono (lib de Google no es async). Para una
    # request sola, no vale la pena pasarlo a un executor — corre
    # en milisegundos. Si en el futuro hacemos sync masivos en
    # background, lo movemos.
    servicio = _servicio_calendar(creds)

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
    saltados_por_conflicto = 0

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
        fila_nueva = _evento_google_a_fila(ev, email)
        google_updated = ev.get("updated")
        existente = await _buscar_existente(db, external_id, email)
        if existente:
            # Last-write-wins: si el hub está más fresco, saltamos.
            if not _aplicar_pull(existente, google_updated):
                saltados_por_conflicto += 1
                continue
            await _actualizar(
                db,
                external_id,
                email,
                fila_nueva,
                google_updated=google_updated,
            )
            actualizados += 1
        else:
            await _insertar(
                db, fila_nueva, google_updated=google_updated
            )
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
        "empujados_a_google": empujados,
        "saltados_por_conflicto": saltados_por_conflicto,
    }


async def _empujar_pendientes(
    db: Postgrest, *, email: str
) -> int:
    """Empuja a Google los eventos manuales del hub que aún no
    tienen `external_id` (backfill). Devuelve cuántos se empujaron
    con éxito. Los que fallen quedan local — el próximo sync los
    reintenta."""
    candidatos = await db.list(
        "eventos",
        filters={"origen": "manual"},
        raw_filters={
            "external_id": "is.null",
            "eliminado_en": "is.null",
        },
    )
    if not candidatos:
        return 0
    empujados = 0
    for fila in candidatos:
        try:
            patch = await push_evento(
                db, email=email, fila=fila, accion="crear"
            )
        except (HttpError, RuntimeError) as e:
            logger.warning(
                "Backfill: no pude empujar evento %s a Google: %s",
                fila.get("id"),
                e,
            )
            continue
        await db.update("eventos", fila["id"], patch)
        empujados += 1
    return empujados


def _aplicar_pull(
    existente: dict[str, Any], google_updated: str | None
) -> bool:
    """Decide si un evento del pull debe sobreescribir al del hub.
    Last-write-wins por timestamp con epsilon de `_EPSILON_CONFLICTO`.

    Si el hub tiene una `actualizado_en` posterior al `google_updated`
    + epsilon, no aplicamos (el hub ganó). Si Google no nos pasó
    `updated`, aplicamos (caso raro pero seguro)."""
    if not google_updated:
        return True
    hub_actualizado = existente.get("actualizado_en")
    if not hub_actualizado:
        return True
    try:
        g = datetime.fromisoformat(google_updated.replace("Z", "+00:00"))
        h = datetime.fromisoformat(hub_actualizado.replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return True
    return g > h + _EPSILON_CONFLICTO


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


async def _buscar_existente(
    db: Postgrest, external_id: str, email: str
) -> dict[str, Any] | None:
    """Devuelve la fila del hub que matchea (external_id,
    external_account) — incluyendo si está en papelera. La usamos
    para last-write-wins y para preservar el `origen` al
    actualizar."""
    filas = await db.list(
        "eventos",
        filters={"external_id": external_id, "external_account": email},
        limit=1,
    )
    return filas[0] if filas else None


async def _insertar(
    db: Postgrest,
    fila: dict[str, Any],
    *,
    google_updated: str | None,
) -> None:
    payload = {**fila}
    if google_updated:
        payload["google_updated_at"] = google_updated
    await db.insert("eventos", payload)


async def _actualizar(
    db: Postgrest,
    external_id: str,
    email: str,
    fila: dict[str, Any],
    *,
    google_updated: str | None,
) -> None:
    """Actualiza el evento existente por (external_id, email).

    - Limpia `eliminado_en` si estaba en papelera — si Google lo
      trae de nuevo, lo restauramos.
    - **NO toca la columna `origen`** — un evento manual que fue
      pusheado y vuelve por el pull sigue siendo manual. Eso evita
      el degrade que rompería la semántica para la app.
    - Guarda `google_updated_at` para que el próximo pull pueda
      hacer last-write-wins correctamente.
    """
    payload = {
        k: v for k, v in fila.items() if k != "origen"
    }
    payload["eliminado_en"] = None
    if google_updated:
        payload["google_updated_at"] = google_updated
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
