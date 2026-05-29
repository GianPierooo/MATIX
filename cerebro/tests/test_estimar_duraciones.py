"""Tests del endpoint `/matix/estimar-duraciones` (Urgencia-3).

No llamamos a OpenAI: monkeypatcheamos `llm.estimar_duraciones_json`.
El encaje de bloques NO se prueba acá — eso es lógica pura de la app.
"""
from __future__ import annotations

import pytest
from httpx import AsyncClient

from app.matix import llm


async def test_estima_devuelve_duraciones(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    async def fake(tareas, *, model="gpt-4o-mini"):  # noqa: ANN001, ARG001
        return {t["id"]: 45 for t in tareas}

    monkeypatch.setattr(llm, "estimar_duraciones_json", fake)
    r = await client.post(
        "/api/v1/matix/estimar-duraciones",
        json={
            "tareas": [
                {"id": "a", "titulo": "Responder correos"},
                {"id": "b", "titulo": "Estudiar cálculo"},
            ]
        },
    )
    assert r.status_code == 200, r.text
    duraciones = {d["tarea_id"]: d["minutos"] for d in r.json()["duraciones"]}
    assert duraciones == {"a": 45, "b": 45}


async def test_lista_vacia_no_llama_al_modelo(client: AsyncClient) -> None:
    r = await client.post(
        "/api/v1/matix/estimar-duraciones", json={"tareas": []}
    )
    assert r.status_code == 200
    assert r.json()["duraciones"] == []


async def test_modelo_falla_502(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    async def fake(tareas, *, model="gpt-4o-mini"):  # noqa: ANN001, ARG001
        raise ValueError("boom")

    monkeypatch.setattr(llm, "estimar_duraciones_json", fake)
    r = await client.post(
        "/api/v1/matix/estimar-duraciones",
        json={"tareas": [{"id": "a", "titulo": "x"}]},
    )
    assert r.status_code == 502


async def test_requiere_api_key(client_anon: AsyncClient) -> None:
    r = await client_anon.post(
        "/api/v1/matix/estimar-duraciones",
        json={"tareas": [{"id": "a", "titulo": "x"}]},
    )
    assert r.status_code == 401
