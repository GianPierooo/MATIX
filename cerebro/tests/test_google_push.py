"""Tests del push bidireccional (Capa 4 Paso 2).

Cubre los 6 escenarios del plan:

1. Push crear: POST /eventos guarda en hub y empuja a Google;
   la fila final tiene `external_id` y `google_updated_at`.
2. Si Google rebota durante el push, el POST igual devuelve 201
   y el evento queda local (lo recoge el backfill).
3. PATCH/DELETE de un evento `origen='manual'` empujan al endpoint
   correcto de Google.
4. PATCH sobre un evento `origen='google'` empuja a Google PRIMERO;
   si Google rebota, el hub NO aplica el cambio (sin desync).
5. Pull no degrada `origen='manual'` a `origen='google'` cuando
   reencuentra el evento por `external_id`.
6. Last-write-wins: si `google_updated <= hub.actualizado_en + 2s`,
   el pull saltea el evento.

Para no llamar a Google real, monkeypatcheamos
`gcal._servicio_calendar` con un fake que registra las llamadas
y devuelve respuestas controladas.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
from unittest.mock import MagicMock

import pytest
from httpx import AsyncClient

from app.google import calendar as gcal
from app.google import oauth as goauth


@pytest.fixture
def fake_google(monkeypatch: pytest.MonkeyPatch) -> dict[str, Any]:
    """Sustituye `_servicio_calendar` por un mock estilo googleapiclient
    (cadena fluida `.events().insert(...).execute()`). Devuelve un dict
    que el test puede inspeccionar para ver qué se llamó.

    También mockea `obtener_credenciales` para evitar leer la BD."""
    estado: dict[str, Any] = {
        "insert_calls": [],
        "patch_calls": [],
        "delete_calls": [],
        # Si está seteado, raise en la próxima llamada.
        "raise_next": None,
        "ultimo_updated": "2026-05-28T16:00:00.000Z",
    }

    def fabricar() -> Any:
        servicio = MagicMock()
        eventos = MagicMock()
        servicio.events.return_value = eventos

        def insert(*, calendarId: str, body: dict) -> Any:  # noqa: N803
            r = MagicMock()

            def execute() -> dict[str, Any]:
                if estado["raise_next"]:
                    e = estado["raise_next"]
                    estado["raise_next"] = None
                    raise e
                estado["insert_calls"].append(
                    {"calendarId": calendarId, "body": body}
                )
                return {
                    "id": f"google-id-{len(estado['insert_calls'])}",
                    "updated": estado["ultimo_updated"],
                }

            r.execute = execute
            return r

        def patch(
            *, calendarId: str, eventId: str, body: dict  # noqa: N803
        ) -> Any:
            r = MagicMock()

            def execute() -> dict[str, Any]:
                if estado["raise_next"]:
                    e = estado["raise_next"]
                    estado["raise_next"] = None
                    raise e
                estado["patch_calls"].append(
                    {
                        "calendarId": calendarId,
                        "eventId": eventId,
                        "body": body,
                    }
                )
                return {
                    "id": eventId,
                    "updated": estado["ultimo_updated"],
                }

            r.execute = execute
            return r

        def delete(
            *, calendarId: str, eventId: str  # noqa: N803
        ) -> Any:
            r = MagicMock()

            def execute() -> None:
                if estado["raise_next"]:
                    e = estado["raise_next"]
                    estado["raise_next"] = None
                    raise e
                estado["delete_calls"].append(
                    {"calendarId": calendarId, "eventId": eventId}
                )

            r.execute = execute
            return r

        eventos.insert.side_effect = insert
        eventos.patch.side_effect = patch
        eventos.delete.side_effect = delete
        return servicio

    monkeypatch.setattr(gcal, "_servicio_calendar", lambda creds: fabricar())  # noqa: ARG005

    # `obtener_credenciales` no necesita tocar la BD en estos tests.
    async def fake_creds(db: Any, email: str) -> object:  # noqa: ARG001
        return object()

    monkeypatch.setattr(goauth, "obtener_credenciales", fake_creds)
    return estado


@pytest.fixture
def google_conectado(monkeypatch: pytest.MonkeyPatch) -> str:
    """Simula que hay una cuenta Google conectada con scope full
    de Calendar. La función `_email_google_si_hay` del router lee
    desde acá sin pegar a la BD."""
    email = "test-bidir@example.com"

    async def fake_cuenta(db: Any) -> dict[str, Any]:  # noqa: ARG001
        return {
            "email": email,
            "scopes": ["https://www.googleapis.com/auth/calendar"],
            "tiene_escritura": True,
            "conectado_en": "2026-05-28T15:00:00+00:00",
            "ultimo_sync_en": None,
        }

    monkeypatch.setattr(goauth, "cuenta_conectada", fake_cuenta)
    return email


@pytest.fixture
def google_desconectado(monkeypatch: pytest.MonkeyPatch) -> None:
    async def fake_cuenta(db: Any) -> None:  # noqa: ARG001
        return None

    monkeypatch.setattr(goauth, "cuenta_conectada", fake_cuenta)


# ─── Tests ───────────────────────────────────────────────────────────


async def test_crear_evento_manual_empuja_a_google(
    client: AsyncClient,
    google_conectado: str,  # noqa: ARG001
    fake_google: dict[str, Any],
) -> None:
    """POST /eventos guarda en hub y empuja a Google. La fila final
    devuelve `external_id` (el que Google asignó) y
    `google_updated_at`. Sin esto, el pull subsiguiente lo
    re-importaría como duplicado."""
    body = {
        "titulo": "_test_push_crear",
        "inicia_en": "2026-06-01T10:00:00+00:00",
        "termina_en": "2026-06-01T11:00:00+00:00",
    }
    r = await client.post("/api/v1/eventos", json=body)
    assert r.status_code == 201, r.text
    creado = r.json()
    try:
        assert creado["external_id"] == "google-id-1"
        assert creado["external_account"] is not None
        assert creado["google_updated_at"] is not None
        # Google recibió un insert al calendar primary con el título.
        assert len(fake_google["insert_calls"]) == 1
        llamada = fake_google["insert_calls"][0]
        assert llamada["calendarId"] == "primary"
        assert llamada["body"]["summary"] == "_test_push_crear"
    finally:
        await client.delete(f"/api/v1/eventos/{creado['id']}/permanente")


async def test_crear_evento_no_falla_si_google_rebota(
    client: AsyncClient,
    google_conectado: str,  # noqa: ARG001
    fake_google: dict[str, Any],
) -> None:
    """Si el push a Google falla, el cliente NO ve error — el evento
    queda local y el siguiente sync lo backfilea. El dato del usuario
    nunca se pierde por una falla upstream."""
    from googleapiclient.errors import HttpError

    fake_google["raise_next"] = HttpError(
        resp=_resp_falsa(500), content=b"boom"
    )
    body = {
        "titulo": "_test_push_rebote",
        "inicia_en": "2026-06-02T10:00:00+00:00",
    }
    r = await client.post("/api/v1/eventos", json=body)
    assert r.status_code == 201, r.text
    creado = r.json()
    try:
        # Se guardó en el hub pero sin external_id (la red de
        # backfill lo va a empujar después).
        assert creado["external_id"] is None
        assert creado["google_updated_at"] is None
    finally:
        await client.delete(f"/api/v1/eventos/{creado['id']}/permanente")


async def test_editar_manual_ya_pusheado_envia_patch_a_google(
    client: AsyncClient,
    google_conectado: str,  # noqa: ARG001
    fake_google: dict[str, Any],
) -> None:
    """Manual ya pusheado: PATCH local → patch en Google con el
    nuevo summary. El `google_updated_at` se refresca."""
    body = {
        "titulo": "_test_editar_v1",
        "inicia_en": "2026-06-03T10:00:00+00:00",
    }
    r = await client.post("/api/v1/eventos", json=body)
    creado = r.json()
    try:
        # Editamos: cambia título.
        fake_google["ultimo_updated"] = "2026-05-28T17:00:00.000Z"
        r2 = await client.patch(
            f"/api/v1/eventos/{creado['id']}",
            json={"titulo": "_test_editar_v2"},
        )
        assert r2.status_code == 200, r2.text
        editado = r2.json()
        assert editado["titulo"] == "_test_editar_v2"
        assert len(fake_google["patch_calls"]) == 1
        llamada = fake_google["patch_calls"][0]
        assert llamada["eventId"] == "google-id-1"
        assert llamada["body"]["summary"] == "_test_editar_v2"
        assert editado["google_updated_at"].startswith("2026-05-28T17:00")
    finally:
        await client.delete(f"/api/v1/eventos/{creado['id']}/permanente")


async def test_editar_split_solo_esta_empuja_nuevo_a_google(
    client: AsyncClient,
    google_conectado: str,  # noqa: ARG001
    fake_google: dict[str, Any],
) -> None:
    """D1: PATCH alcance=solo_esta sobre una serie manual ya pusheada crea un
    evento ÚNICO nuevo y lo empuja a Google como CREACIÓN (2do insert). Antes el
    split se quedaba local esperando el próximo pull."""
    body = {
        "titulo": "_test_split_v1",
        "inicia_en": "2026-06-01T08:00:00-05:00",
        "termina_en": "2026-06-01T09:00:00-05:00",
        "recurrencia_freq": "semanal",
        "recurrencia_dias_semana": [1, 3],
        "recurrencia_fin_tipo": "nunca",
    }
    r = await client.post("/api/v1/eventos", json=body)
    assert r.status_code == 201, r.text
    creado = r.json()
    assert creado["external_id"] == "google-id-1"  # la serie se pusheó
    nuevo_id = None
    try:
        r2 = await client.patch(
            f"/api/v1/eventos/{creado['id']}?alcance=solo_esta&ocurrencia_fecha=2026-06-03",
            json={"titulo": "_test_split_esta"},
        )
        assert r2.status_code == 200, r2.text
        nuevo = r2.json()
        nuevo_id = nuevo["id"]
        assert nuevo_id != creado["id"]                 # es un evento NUEVO (único)
        assert len(fake_google["insert_calls"]) == 2    # el split se empujó a Google
        assert nuevo["external_id"] == "google-id-2"
        assert fake_google["insert_calls"][1]["body"]["summary"] == "_test_split_esta"
    finally:
        await client.delete(f"/api/v1/eventos/{creado['id']}/permanente")
        if nuevo_id:
            await client.delete(f"/api/v1/eventos/{nuevo_id}/permanente")


async def test_borrar_manual_ya_pusheado_envia_delete_a_google(
    client: AsyncClient,
    google_conectado: str,  # noqa: ARG001
    fake_google: dict[str, Any],
) -> None:
    """DELETE local → DELETE en Google + soft-delete en hub."""
    body = {
        "titulo": "_test_borrar_push",
        "inicia_en": "2026-06-04T10:00:00+00:00",
    }
    r = await client.post("/api/v1/eventos", json=body)
    creado = r.json()
    try:
        r2 = await client.delete(f"/api/v1/eventos/{creado['id']}")
        assert r2.status_code == 204, r2.text
        assert len(fake_google["delete_calls"]) == 1
        assert fake_google["delete_calls"][0]["eventId"] == "google-id-1"
    finally:
        await client.delete(f"/api/v1/eventos/{creado['id']}/permanente")


async def test_editar_origen_google_falla_si_google_rebota(
    client: AsyncClient,
    google_conectado: str,  # noqa: ARG001
    fake_google: dict[str, Any],
) -> None:
    """Para `origen='google'` el flujo es Google-primero. Si Google
    rebota (ej. 403 porque el user no es organizador), el hub NO
    aplica el cambio y el endpoint devuelve el error.
    """
    # Sembramos un evento `origen='google'` directamente en la BD
    # (sin pasar por el POST porque ése es para manuales).
    from app.db import Postgrest

    pg = Postgrest()
    try:
        fila = await pg.insert(
            "eventos",
            {
                "titulo": "_test_origen_google_v1",
                "inicia_en": "2026-06-05T10:00:00+00:00",
                "origen": "google",
                "external_id": "evento-de-otra-persona-1",
                "external_account": "test-bidir@example.com",
            },
        )
        evento_id = fila["id"]

        from googleapiclient.errors import HttpError

        fake_google["raise_next"] = HttpError(
            resp=_resp_falsa(403), content=b"no organizer"
        )
        r = await client.patch(
            f"/api/v1/eventos/{evento_id}",
            json={"titulo": "_test_origen_google_v2"},
        )
        assert r.status_code == 403, r.text

        # El hub NO aplicó el cambio (sin desync).
        leido = await pg.get("eventos", evento_id)
        assert leido is not None
        assert leido["titulo"] == "_test_origen_google_v1"
    finally:
        await pg.delete("eventos", evento_id)
        await pg.aclose()


async def test_pull_no_degrada_origen_manual_a_google(
    monkeypatch: pytest.MonkeyPatch,
    google_conectado: str,
    fake_google: dict[str, Any],  # noqa: ARG001
) -> None:
    """Un manual con external_id (porque ya lo empujamos) reaparece
    en el pull. El sync lo encuentra por (external_id, email) y lo
    actualiza, pero NO lo convierte en `origen='google'` — sino
    perderíamos la semántica de 'lo creé yo en Matix'."""
    from app.db import Postgrest

    pg = Postgrest()
    try:
        # Sembramos: evento manual ya pusheado.
        external_id = "pushed-manual-1"
        fila = await pg.insert(
            "eventos",
            {
                "titulo": "_test_pull_no_degrada_v1",
                "inicia_en": "2026-06-06T10:00:00+00:00",
                "origen": "manual",
                "external_id": external_id,
                "external_account": google_conectado,
                "google_updated_at": "2026-05-28T10:00:00+00:00",
            },
        )
        evento_id = fila["id"]

        # Simulamos un pull que trae ese mismo evento de Google,
        # con `updated` posterior a `actualizado_en` del hub.
        # Mockeamos la lista de Google con un evento que coincide.
        from app.google import calendar as gcal

        class _FakeServicio:
            def events(self) -> Any:  # noqa: N802
                outer = self

                class _Eventos:
                    def list(self_, **kwargs: Any) -> Any:  # noqa: ARG002, N803
                        r = MagicMock()
                        r.execute = lambda: {
                            "items": [
                                {
                                    "id": external_id,
                                    "status": "confirmed",
                                    "summary": "_test_pull_no_degrada_v2",
                                    "start": {
                                        "dateTime": "2026-06-06T10:00:00+00:00"
                                    },
                                    "end": {
                                        "dateTime": "2026-06-06T11:00:00+00:00"
                                    },
                                    "updated": "2030-01-01T00:00:00.000Z",
                                }
                            ],
                            "nextPageToken": None,
                        }
                        return r

                return _Eventos()

        monkeypatch.setattr(
            gcal, "_servicio_calendar", lambda creds: _FakeServicio()  # noqa: ARG005
        )
        monkeypatch.setattr(
            gcal._empujar_pendientes,
            "__call__",
            lambda *a, **k: 0,
            raising=False,
        )

        # Bypass `marcar_sync` para no tocar `ultimo_sync_en` real.
        async def fake_marcar(db: Any, email: str) -> None:  # noqa: ARG001
            return None

        monkeypatch.setattr(goauth, "marcar_sync", fake_marcar)

        # Para evitar que el backfill empuje otros eventos manuales
        # del proyecto, neutralizamos `_empujar_pendientes`.
        async def fake_pendientes(db: Any, *, email: str) -> int:  # noqa: ARG001
            return 0

        monkeypatch.setattr(gcal, "_empujar_pendientes", fake_pendientes)

        resumen = await gcal.sincronizar(pg, google_conectado)
        assert resumen["actualizados"] >= 1

        # Releemos: título nuevo, origen sigue siendo "manual".
        leido = await pg.get("eventos", evento_id)
        assert leido is not None
        assert leido["titulo"] == "_test_pull_no_degrada_v2"
        assert leido["origen"] == "manual"
    finally:
        await pg.delete("eventos", evento_id)
        await pg.aclose()


def test_aplicar_pull_respeta_last_write_wins() -> None:
    """Unit-test puro de la decisión de last-write-wins. Si
    `google_updated <= hub.actualizado_en + 2s`, no aplicamos."""
    base = datetime(2026, 5, 28, 10, 0, 0, tzinfo=timezone.utc).isoformat()
    # Hub es claramente más nuevo → no aplicar.
    futuro_hub = datetime(2026, 5, 28, 11, 0, 0, tzinfo=timezone.utc).isoformat()
    assert (
        gcal._aplicar_pull({"actualizado_en": futuro_hub}, base) is False
    )
    # Google es claramente más nuevo → aplicar.
    futuro_google = datetime(
        2026, 5, 28, 12, 0, 0, tzinfo=timezone.utc
    ).isoformat()
    assert (
        gcal._aplicar_pull({"actualizado_en": base}, futuro_google) is True
    )
    # Diferencia <= 2s → no aplicar (asume eco de nuestro push).
    casi_igual = datetime(
        2026, 5, 28, 10, 0, 1, tzinfo=timezone.utc
    ).isoformat()
    assert gcal._aplicar_pull({"actualizado_en": base}, casi_igual) is False


# ─── helpers ─────────────────────────────────────────────────────────


def _resp_falsa(status: int) -> Any:
    """Fabrica el objeto de respuesta que el constructor de
    `HttpError` necesita (atributo `status`)."""
    r = MagicMock()
    r.status = status
    r.reason = "test"
    return r
