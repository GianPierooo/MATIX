"""Tests del flujo OAuth Google (Capa 4 Paso 1).

Cubre el bug que vimos en producción: `invalid_grant: Missing code
verifier`. google-auth-oauthlib activa PKCE por defecto, así que al
armar la auth URL se genera un `code_verifier` y se manda el
`code_challenge` derivado a Google. Si el callback crea un Flow
fresco sin recuperar el verifier original, el intercambio code→tokens
falla.

Estos tests verifican:

1. Al generar la URL, el `code_verifier` queda persistido indexado
   por `state` en `_PENDING_STATES`, y la URL incluye
   `code_challenge`/`code_challenge_method` para Google.
2. El callback recupera el verifier para ese `state` y lo pasa a
   `completar_autorizacion`.
3. `completar_autorizacion` settea el verifier en el Flow antes de
   `fetch_token`, así Google recibe `code_verifier=<el correcto>` y
   el intercambio cierra OK.
4. State desconocido en el callback se rechaza (defensa CSRF).
"""
from __future__ import annotations

from typing import Any
from urllib.parse import parse_qs, urlparse

import pytest
from httpx import AsyncClient

from app.google import oauth as goauth
from app.routers import google as google_router


@pytest.fixture(autouse=True)
def _google_configurado(monkeypatch: pytest.MonkeyPatch) -> None:
    """Setea credenciales OAuth ficticias para que los endpoints no
    devuelvan 503. Los tests no llaman a Google real."""
    from app.config import settings

    monkeypatch.setattr(settings, "google_client_id", "fake-client-id")
    monkeypatch.setattr(settings, "google_client_secret", "fake-secret")
    monkeypatch.setattr(
        settings,
        "google_redirect_uri",
        "http://localhost:8000/api/v1/google/oauth/callback",
    )


@pytest.fixture(autouse=True)
def _limpiar_estados_pendientes() -> Any:
    """Cada test arranca con el dict de states vacío."""
    google_router._PENDING_STATES.clear()
    yield
    google_router._PENDING_STATES.clear()


async def test_url_persiste_verifier_y_manda_challenge_a_google(
    client: AsyncClient,
) -> None:
    """La URL de auth debe llevar `code_challenge` + `code_challenge_method`,
    y el `code_verifier` del Flow tiene que quedar guardado en
    `_PENDING_STATES` indexado por el state devuelto."""
    r = await client.get("/api/v1/google/oauth/url")
    assert r.status_code == 200, r.text
    body = r.json()
    state = body["state"]
    url = body["url"]

    # El state quedó persistido con un verifier no-vacío.
    assert state in google_router._PENDING_STATES
    verifier = google_router._PENDING_STATES[state]["code_verifier"]
    assert verifier
    # El verifier de PKCE es 43-128 chars, charset URL-safe (RFC 7636).
    assert 43 <= len(verifier) <= 128

    # Google recibe en la URL el challenge derivado.
    q = parse_qs(urlparse(url).query)
    assert q.get("code_challenge"), "la URL no incluye code_challenge"
    assert q.get("code_challenge_method") == ["S256"]
    # Y el verifier NO debe ir en la URL — solo el challenge.
    assert "code_verifier" not in q


async def test_callback_recupera_verifier_y_se_lo_pasa_al_exchange(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """El callback debe sacar el verifier guardado para `state` y
    pasarlo a `completar_autorizacion`. Es el agujero exacto que
    causaba `invalid_grant: Missing code verifier`."""
    r = await client.get("/api/v1/google/oauth/url")
    state = r.json()["state"]
    verifier_guardado = google_router._PENDING_STATES[state]["code_verifier"]

    # Capturamos lo que recibe `completar_autorizacion` sin tocar la BD.
    capturado: dict[str, Any] = {}

    async def fake_completar(db: Any, *, code: str, state: str, code_verifier: str) -> str:  # noqa: ARG001
        capturado["code"] = code
        capturado["state"] = state
        capturado["code_verifier"] = code_verifier
        return "test@example.com"

    async def fake_sync(db: Any, email: str) -> dict[str, int]:  # noqa: ARG001
        return {"creados": 0, "actualizados": 0}

    monkeypatch.setattr(google_router.goauth, "completar_autorizacion", fake_completar)
    monkeypatch.setattr(google_router.gcal, "sincronizar", fake_sync)

    r2 = await client.get(
        "/api/v1/google/oauth/callback",
        params={"code": "fake-auth-code", "state": state},
    )
    assert r2.status_code == 200, r2.text
    assert "test@example.com" in r2.text

    assert capturado["code"] == "fake-auth-code"
    assert capturado["state"] == state
    assert capturado["code_verifier"] == verifier_guardado

    # El state se consumió — un segundo callback con el mismo state debe fallar.
    assert state not in google_router._PENDING_STATES


async def test_callback_con_state_desconocido_falla(
    client: AsyncClient,
) -> None:
    """Defensa CSRF: si el state no está en `_PENDING_STATES`, no
    arrancamos el intercambio. Antes el chequeo era `set.__contains__`
    + `discard`; ahora es `dict.pop(...)`, conservamos la semántica."""
    r = await client.get(
        "/api/v1/google/oauth/callback",
        params={"code": "x", "state": "state-que-nunca-generamos"},
    )
    assert r.status_code == 400


async def test_completar_autorizacion_setea_verifier_en_el_flow(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Bajo nivel: `completar_autorizacion` tiene que setear
    `flow.code_verifier` (y desactivar el autogenerate) antes de
    `fetch_token`. Si no, google-auth-oauthlib genera uno NUEVO en
    `authorization_url`/`fetch_token` (distinto al que Google espera)
    o no manda ninguno, y el exchange falla."""
    from datetime import datetime, timedelta, timezone

    from google_auth_oauthlib.flow import Flow

    capturado: dict[str, Any] = {}
    original_fetch = Flow.fetch_token

    def fake_fetch_token(self: Flow, **kwargs: Any) -> dict[str, Any]:  # noqa: ARG001
        capturado["code_verifier_en_flow"] = self.code_verifier
        capturado["autogenerate"] = self.autogenerate_code_verifier
        # Simulamos lo que google-auth deja después de un fetch exitoso.
        from google.oauth2.credentials import Credentials

        self._client_config["token"] = "fake-access"  # type: ignore[attr-defined]
        self.oauth2session.token = {  # type: ignore[attr-defined]
            "access_token": "fake-access",
            "refresh_token": "fake-refresh",
            "id_token": "fake-id-token",
            "expires_at": (
                datetime.now(timezone.utc) + timedelta(hours=1)
            ).timestamp(),
            "scope": goauth.SCOPES_PASO_1,
        }
        # Sortear el property `credentials`: la lib lo arma desde
        # `oauth2session.token`. Para no depender de internals, dejamos
        # que el código real lo evalúe — si capturamos lo que
        # necesitamos (el verifier seteado), el test ya pasó incluso
        # si la post-creación de creds rompe.
        return self.oauth2session.token  # type: ignore[no-any-return]

    monkeypatch.setattr(Flow, "fetch_token", fake_fetch_token)
    # Cortocircuitamos el resto: el email lo provee `_extraer_email`,
    # y el DB upsert lo bypasseamos.
    monkeypatch.setattr(goauth, "_extraer_email", lambda creds: "u@example.com")  # noqa: ARG005

    class _FakeHttp:
        async def post(self, *args: Any, **kwargs: Any) -> None: ...

    class _FakeDb:
        _http = _FakeHttp()

    try:
        await goauth.completar_autorizacion(
            _FakeDb(),  # type: ignore[arg-type]
            code="any",
            state="any",
            code_verifier="verifier-de-prueba-43-chars-minimo-aaaaaaaaaa",
        )
    except Exception:
        # No nos importa si el armado de Credentials post-fetch falla
        # en este mock — lo único que validamos es que el verifier
        # llegó al Flow ANTES del fetch.
        pass

    # Restaurar para no contaminar otros tests.
    monkeypatch.setattr(Flow, "fetch_token", original_fetch)

    assert capturado["code_verifier_en_flow"] == (
        "verifier-de-prueba-43-chars-minimo-aaaaaaaaaa"
    )
    assert capturado["autogenerate"] is False
