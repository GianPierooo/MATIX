"""Tests del repaso semanal (Capa 8 · Repaso).

- El fallback determinístico (sin LLM) arma un resumen honesto + focos.
- El endpoint integra: con el LLM mockeado devuelve resumen/focos del
  modelo; las tareas que se pasaron llegan con id (para reprogramar).
"""
from __future__ import annotations

import pytest
from httpx import AsyncClient

from app.briefing import repaso_semanal
from app.matix import llm


def test_fallback_reconoce_lo_hecho_y_lo_que_quedo() -> None:
    resumen, focos = repaso_semanal._fallback(
        completadas=3, n_vencidas=2, eventos=1
    )
    assert "3 tareas" in resumen
    assert "2 quedaron" in resumen
    assert len(focos) >= 1
    # Si hay vencidas, sugiere reprogramar.
    assert any("eprograma" in f or "pas" in f for f in focos)


def test_fallback_sin_nada_no_culpabiliza() -> None:
    resumen, focos = repaso_semanal._fallback(
        completadas=0, n_vencidas=0, eventos=0
    )
    assert "está bien" in resumen
    assert len(focos) >= 1


async def test_endpoint_repaso_con_llm_mockeado(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    async def fake(datos, *, model="gpt-4o-mini"):  # noqa: ANN001, ARG001
        return {
            "resumen": "Buena semana: avanzaste y quedó poco suelto.",
            "focos": ["Cerrar lo pendiente", "Avanzar la tesis"],
        }

    monkeypatch.setattr(llm, "repaso_semanal_json", fake)
    r = await client.get("/api/v1/briefing/repaso-semanal")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["resumen"].startswith("Buena semana")
    assert body["focos"] == ["Cerrar lo pendiente", "Avanzar la tesis"]
    assert "semana_desde" in body and "semana_hasta" in body
    assert isinstance(body["vencidas"], list)


async def test_endpoint_repaso_sin_llm_usa_fallback(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    async def boom(datos, *, model="gpt-4o-mini"):  # noqa: ANN001, ARG001
        raise RuntimeError("sin OPENAI_API_KEY")

    monkeypatch.setattr(llm, "repaso_semanal_json", boom)
    r = await client.get("/api/v1/briefing/repaso-semanal")
    # Nunca falla: cae al resumen determinístico.
    assert r.status_code == 200, r.text
    assert r.json()["resumen"]


async def test_requiere_api_key(client_anon: AsyncClient) -> None:
    r = await client_anon.get("/api/v1/briefing/repaso-semanal")
    assert r.status_code == 401
