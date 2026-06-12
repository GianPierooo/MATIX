"""Flujo OAuth Spotify DESDE LA APP (Capa 6 · reproducir en la PC).

El usuario conecta su Premium desde Ajustes: la app abre la URL de consentimiento,
Spotify redirige al /callback PÚBLICO del cerebro, que intercambia el code por el
refresh token. Cubre: la URL lleva los scopes y el state persiste; el callback
con state válido intercambia y con state desconocido se rechaza (CSRF); el
/callback NO exige X-Matix-Key (Spotify no la manda).
"""
from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient

from app.routers import spotify as spotify_router


@pytest.fixture(autouse=True)
def _creds_y_estados(monkeypatch: pytest.MonkeyPatch) -> Any:
    monkeypatch.setenv("SPOTIFY_CLIENT_ID", "cid-test")
    monkeypatch.setenv("SPOTIFY_CLIENT_SECRET", "sec-test")
    monkeypatch.delenv("SPOTIFY_REFRESH_TOKEN", raising=False)
    from app.matix import secretos, spotify_web
    spotify_web._limpiar_cache()
    secretos._limpiar_cache()
    spotify_router._PENDING_STATES.clear()
    yield
    spotify_router._PENDING_STATES.clear()


async def test_oauth_url_lleva_scopes_y_persiste_state(client: AsyncClient) -> None:
    r = await client.get("/api/v1/spotify/oauth/url")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["state"] in spotify_router._PENDING_STATES
    assert "user-modify-playback-state" in body["url"]
    assert "user-read-playback-state" in body["url"]
    assert "accounts.spotify.com/authorize" in body["url"]


async def test_callback_state_valido_intercambia(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    r = await client.get("/api/v1/spotify/oauth/url")
    state = r.json()["state"]

    capt: dict[str, Any] = {}

    async def fake_intercambiar(code: str, cliente: Any = None) -> bool:  # noqa: ARG001
        capt["code"] = code
        return True

    monkeypatch.setattr(spotify_router.spotify_web, "intercambiar_code", fake_intercambiar)
    r2 = await client.get("/api/v1/spotify/callback", params={"code": "auth-code", "state": state})
    assert r2.status_code == 200, r2.text
    assert capt["code"] == "auth-code"
    assert "conectado" in r2.text.lower()
    # El state se consume (un solo uso).
    assert state not in spotify_router._PENDING_STATES


async def test_callback_state_desconocido_rechaza(client: AsyncClient) -> None:
    r = await client.get("/api/v1/spotify/callback", params={"code": "x", "state": "inventado"})
    assert r.status_code == 400
    assert "expir" in r.text.lower() or "coincide" in r.text.lower()


async def test_callback_con_error_de_spotify(client: AsyncClient) -> None:
    r = await client.get("/api/v1/spotify/callback", params={"state": "x", "error": "access_denied"})
    assert r.status_code == 400
    assert "access_denied" in r.text


async def test_callback_no_exige_api_key(client_anon: AsyncClient) -> None:
    # El /callback es PÚBLICO (Spotify no manda X-Matix-Key): un state inventado
    # da 400 (no 401/403). Si exigiera auth, daría 401 antes de mirar el state.
    r = await client_anon.get("/api/v1/spotify/callback", params={"code": "x", "state": "z"})
    assert r.status_code == 400


async def test_status_refleja_conexion(client: AsyncClient) -> None:
    r = await client.get("/api/v1/spotify/status")
    assert r.status_code == 200
    body = r.json()
    assert body["conectado"] is False  # sin refresh token
    assert body["busqueda_disponible"] is True  # id+secret presentes
