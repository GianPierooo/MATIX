"""Tests de push / FCM (Push Capa 1).

Registro de token (upsert en device_tokens) y el endpoint de prueba. NO
pegamos a Firebase: monkeypatcheamos `push.enviar_push`. Requiere el
Supabase de test con la migración 0016 aplicada. Los tokens `_test_…` los
limpia el barrido de residuos del conftest.
"""
from __future__ import annotations

from httpx import AsyncClient

from app.routers import push as push_router


async def test_registrar_token_es_idempotente(client: AsyncClient) -> None:
    token = "_test_fcm_token_abc123"
    r1 = await client.post(
        "/api/v1/push/registrar-token",
        json={"token": token, "plataforma": "android"},
    )
    assert r1.status_code == 200, r1.text
    assert r1.json()["ok"] is True

    # Re-registrar el mismo token no duplica ni revienta por el unique.
    r2 = await client.post(
        "/api/v1/push/registrar-token",
        json={"token": token, "plataforma": "android"},
    )
    assert r2.status_code == 200, r2.text


async def test_probar_envia_al_token_dado(
    client: AsyncClient, monkeypatch
) -> None:
    enviados: list[str] = []

    def fake_enviar(token, *, titulo, cuerpo):
        enviados.append(token)
        return "projects/x/messages/fake-id-123456"

    monkeypatch.setattr(push_router, "enviar_push", fake_enviar)

    r = await client.post(
        "/api/v1/push/probar",
        json={"token": "_test_token_directo", "titulo": "Hola", "cuerpo": "Mundo"},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["enviados"] == 1
    assert body["fallidos"] == 0
    assert enviados == ["_test_token_directo"]


async def test_token_vacio_es_400(client: AsyncClient) -> None:
    r = await client.post(
        "/api/v1/push/registrar-token", json={"token": "   "}
    )
    assert r.status_code == 400, r.text
