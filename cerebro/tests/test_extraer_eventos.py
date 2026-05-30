"""Tests del endpoint `/matix/extraer-eventos` (Cámara · sílabo).

No llamamos a OpenAI: monkeypatcheamos `llm.extraer_eventos_json`.
La distinción recurrente/único y el parseo se prueban en `test_llm_*`
(funciones puras de validación) abajo.
"""
from __future__ import annotations

import pytest
from httpx import AsyncClient

from app.matix import llm


async def test_extrae_recurrentes_y_unicos(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    async def fake(texto, *, hoy, model="gpt-4o-mini"):  # noqa: ANN001, ARG001
        return [
            {
                "tipo": "recurrente",
                "titulo": "Cálculo III",
                "dias_semana": [1, 3],
                "hora_inicio": "10:00",
                "hora_fin": "12:00",
                "fecha": None,
            },
            {
                "tipo": "unico",
                "titulo": "Parcial",
                "dias_semana": [],
                "hora_inicio": "08:00",
                "hora_fin": None,
                "fecha": "2026-04-15",
            },
        ]

    monkeypatch.setattr(llm, "extraer_eventos_json", fake)
    r = await client.post(
        "/api/v1/matix/extraer-eventos",
        json={"texto": "Cálculo III lunes y miércoles 10-12. Parcial 15 abril."},
    )
    assert r.status_code == 200, r.text
    eventos = r.json()["eventos"]
    assert len(eventos) == 2
    rec = eventos[0]
    assert rec["tipo"] == "recurrente" and rec["dias_semana"] == [1, 3]
    uni = eventos[1]
    assert uni["tipo"] == "unico" and uni["fecha"] == "2026-04-15"


async def test_texto_vacio_422(client: AsyncClient) -> None:
    r = await client.post("/api/v1/matix/extraer-eventos", json={"texto": ""})
    assert r.status_code == 422


async def test_modelo_falla_502(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    async def fake(texto, *, hoy, model="gpt-4o-mini"):  # noqa: ANN001, ARG001
        raise ValueError("boom")

    monkeypatch.setattr(llm, "extraer_eventos_json", fake)
    r = await client.post(
        "/api/v1/matix/extraer-eventos", json={"texto": "algo"}
    )
    assert r.status_code == 502


async def test_requiere_api_key(client_anon: AsyncClient) -> None:
    r = await client_anon.post(
        "/api/v1/matix/extraer-eventos", json={"texto": "x"}
    )
    assert r.status_code == 401


def test_hhmm_valido() -> None:
    assert llm._hhmm_valido("10:00") == "10:00"
    assert llm._hhmm_valido("9:5") == "09:05"
    assert llm._hhmm_valido("25:00") is None
    assert llm._hhmm_valido("mediodía") is None
    assert llm._hhmm_valido(None) is None
