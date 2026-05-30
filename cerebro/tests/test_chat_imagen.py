"""Tests del chat multimodal (imagen → Matix la ve).

- `conversar` con imagen arma el mensaje de usuario como contenido
  multimodal [texto, image_url] que entiende gpt-4o-mini (LLM mockeado).
- El endpoint rechaza data URLs inválidos (400) e imágenes muy pesadas
  (413), con mensaje claro.
"""
from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient

from app.matix import chat as chat_mod

_DATA_URL = "data:image/jpeg;base64,/9j/4AAQSkZJRg=="


async def test_conversar_arma_contenido_multimodal(
    _fresh_db, monkeypatch: pytest.MonkeyPatch
) -> None:
    capturado: dict[str, Any] = {}

    async def fake(messages, tools, tool_choice=None):  # noqa: ANN001, ARG001
        capturado["messages"] = messages
        return {"tipo": "texto", "contenido": "Veo un gato.", "raw": {}}

    monkeypatch.setattr(chat_mod.llm, "responder_con_tools", fake)

    res = await chat_mod.conversar(
        _fresh_db,
        historial=[],
        mensaje="¿Qué ves?",
        imagen=_DATA_URL,
    )
    assert res["respuesta"] == "Veo un gato."

    # El último mensaje (turno actual) debe ser multimodal con la imagen.
    ultimo = capturado["messages"][-1]
    assert ultimo["role"] == "user"
    partes = ultimo["content"]
    assert isinstance(partes, list)
    tipos = {p["type"] for p in partes}
    assert tipos == {"text", "image_url"}
    img = next(p for p in partes if p["type"] == "image_url")
    assert img["image_url"]["url"] == _DATA_URL


async def test_conversar_sin_imagen_es_texto_plano(
    _fresh_db, monkeypatch: pytest.MonkeyPatch
) -> None:
    capturado: dict[str, Any] = {}

    async def fake(messages, tools, tool_choice=None):  # noqa: ANN001, ARG001
        capturado["messages"] = messages
        return {"tipo": "texto", "contenido": "Hola.", "raw": {}}

    monkeypatch.setattr(chat_mod.llm, "responder_con_tools", fake)
    await chat_mod.conversar(_fresh_db, historial=[], mensaje="hola")
    assert capturado["messages"][-1]["content"] == "hola"


async def test_endpoint_rechaza_data_url_invalido(client: AsyncClient) -> None:
    r = await client.post(
        "/api/v1/matix/chat",
        json={"mensaje": "mira", "imagen": "no-soy-una-data-url"},
    )
    assert r.status_code == 400


async def test_endpoint_rechaza_imagen_muy_pesada(client: AsyncClient) -> None:
    pesada = "data:image/jpeg;base64," + ("A" * 7_000_001)
    r = await client.post(
        "/api/v1/matix/chat",
        json={"mensaje": "mira", "imagen": pesada},
    )
    assert r.status_code == 413


async def test_chat_requiere_api_key(client_anon: AsyncClient) -> None:
    r = await client_anon.post(
        "/api/v1/matix/chat", json={"mensaje": "hola"}
    )
    assert r.status_code == 401
