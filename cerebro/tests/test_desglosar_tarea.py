"""Tests del endpoint `/matix/desglosar-tarea` (Capa 7 · Desglose).

No llamamos a OpenAI: monkeypatcheamos `llm.desglosar_tarea_json`.
"""
from __future__ import annotations

import pytest
from httpx import AsyncClient

from app.matix import llm


async def test_desglosa_devuelve_pasos(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    async def fake(titulo, *, contexto=None, model="gpt-4o-mini"):  # noqa: ANN001, ARG001
        return {
            "es_atomica": False,
            "pasos": [
                {"titulo": "Elegir tema", "horizonte": "ahora"},
                {"titulo": "Revisar literatura", "horizonte": "pronto"},
            ],
        }

    monkeypatch.setattr(llm, "desglosar_tarea_json", fake)
    r = await client.post(
        "/api/v1/matix/desglosar-tarea", json={"titulo": "Hacer la tesis"}
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["es_atomica"] is False
    assert [p["titulo"] for p in body["pasos"]] == [
        "Elegir tema",
        "Revisar literatura",
    ]
    assert body["pasos"][0]["horizonte"] == "ahora"


async def test_tarea_atomica_no_se_infla(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    async def fake(titulo, *, contexto=None, model="gpt-4o-mini"):  # noqa: ANN001, ARG001
        return {"es_atomica": True, "pasos": []}

    monkeypatch.setattr(llm, "desglosar_tarea_json", fake)
    r = await client.post(
        "/api/v1/matix/desglosar-tarea", json={"titulo": "Comprar pan"}
    )
    assert r.status_code == 200
    body = r.json()
    assert body["es_atomica"] is True
    assert body["pasos"] == []


async def test_titulo_vacio_422(client: AsyncClient) -> None:
    r = await client.post("/api/v1/matix/desglosar-tarea", json={"titulo": ""})
    assert r.status_code == 422


async def test_modelo_falla_502(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    async def fake(titulo, *, contexto=None, model="gpt-4o-mini"):  # noqa: ANN001, ARG001
        raise ValueError("boom")

    monkeypatch.setattr(llm, "desglosar_tarea_json", fake)
    r = await client.post(
        "/api/v1/matix/desglosar-tarea", json={"titulo": "x"}
    )
    assert r.status_code == 502


async def test_requiere_api_key(client_anon: AsyncClient) -> None:
    r = await client_anon.post(
        "/api/v1/matix/desglosar-tarea", json={"titulo": "x"}
    )
    assert r.status_code == 401
