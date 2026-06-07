"""Failover entre proveedores del LLM (patrón barato y legítimo).

Mockeamos `llm._con_tools_en` (el intento contra UN modelo) para no tocar red
ni necesitar las API keys. Probamos: primario OK (sin failover), primario falla
por error de PROVEEDOR (failover al otro), primario falla por bad request (NO
failover).
"""
from __future__ import annotations

import pytest

from app.matix import llm, modelos_llm


# Excepciones de juguete que imitan a las de los SDKs.
class RateLimitError(Exception):  # nombre que el clasificador reconoce
    pass


class BadRequestError(Exception):
    def __init__(self) -> None:
        self.status_code = 400
        super().__init__("bad request")


class ServerError(Exception):
    def __init__(self) -> None:
        self.status_code = 503
        super().__init__("upstream caído")


# ── Clasificador de errores ─────────────────────────────────────────


def test_clasificador_proveedor_vs_legitimo():
    assert llm._es_error_de_proveedor(RateLimitError()) is True
    assert llm._es_error_de_proveedor(ServerError()) is True  # 5xx
    # bad request / content filter / auth → NO failover
    assert llm._es_error_de_proveedor(BadRequestError()) is False
    auth = Exception()
    auth.status_code = 401  # type: ignore[attr-defined]
    assert llm._es_error_de_proveedor(auth) is False


# ── Mapa de fallback cruzado ────────────────────────────────────────


def test_fallback_cruza_de_proveedor():
    # rápido↔rápido, a fondo↔a fondo, y SIEMPRE cambia de proveedor.
    fb = modelos_llm.modelo_fallback("gpt-4o-mini")
    assert modelos_llm.proveedor_de_id(fb) == "anthropic"
    fb2 = modelos_llm.modelo_fallback("claude-sonnet-4-6")
    assert modelos_llm.proveedor_de_id(fb2) == "openai"
    # id desconocido openai → barato del otro proveedor (anthropic)
    fb3 = modelos_llm.modelo_fallback("gpt-algo-nuevo")
    assert modelos_llm.proveedor_de_id(fb3) == "anthropic"


# ── Failover en responder_con_tools ─────────────────────────────────


@pytest.mark.asyncio
async def test_primario_ok_sin_failover(monkeypatch):
    async def fake_en(model, messages, tools, *, temperature, tool_choice):
        return {"tipo": "texto", "contenido": "ok", "raw": {"m": model}}

    monkeypatch.setattr(llm, "_con_tools_en", fake_en)
    # Pin a 'auto' para que no haya swap por proveedor preferido en este test.
    monkeypatch.setattr(llm.modelos_llm, "proveedor_preferido", lambda: "auto")
    res = await llm.responder_con_tools([], [], model="gpt-4o-mini")
    assert res["contenido"] == "ok"
    # Contrato nuevo: SIEMPRE se reporta el modelo real; sin failover -> False.
    assert res["failover"] is False
    assert res["modelo_efectivo"] == "gpt-4o-mini"


@pytest.mark.asyncio
async def test_error_de_proveedor_hace_failover(monkeypatch):
    llamadas: list[str] = []

    async def fake_en(model, messages, tools, *, temperature, tool_choice):
        llamadas.append(model)
        if model == "gpt-4o-mini":
            raise RateLimitError()  # proveedor primario caído
        return {"tipo": "texto", "contenido": "desde fallback", "raw": {}}

    monkeypatch.setattr(llm, "_con_tools_en", fake_en)
    res = await llm.responder_con_tools([], [], model="gpt-4o-mini")
    assert res["failover"] is True
    assert res["modelo_efectivo"] == "claude-haiku-4-5"
    assert modelos_llm.proveedor_de_id(res["modelo_efectivo"]) == "anthropic"
    assert res["contenido"] == "desde fallback"
    # UN solo intento de fallback: primario + fallback, nada más.
    assert llamadas == ["gpt-4o-mini", "claude-haiku-4-5"]


@pytest.mark.asyncio
async def test_bad_request_no_hace_failover(monkeypatch):
    llamadas: list[str] = []

    async def fake_en(model, messages, tools, *, temperature, tool_choice):
        llamadas.append(model)
        raise BadRequestError()  # error legítimo

    monkeypatch.setattr(llm, "_con_tools_en", fake_en)
    with pytest.raises(BadRequestError):
        await llm.responder_con_tools([], [], model="gpt-4o-mini")
    # NO reintentó: solo el primario.
    assert llamadas == ["gpt-4o-mini"]


@pytest.mark.asyncio
async def test_fallback_tambien_falla_propaga_sin_loop(monkeypatch):
    llamadas: list[str] = []

    async def fake_en(model, messages, tools, *, temperature, tool_choice):
        llamadas.append(model)
        raise ServerError()  # ambos proveedores caídos

    monkeypatch.setattr(llm, "_con_tools_en", fake_en)
    with pytest.raises(ServerError):
        await llm.responder_con_tools([], [], model="gpt-4o-mini")
    # Exactamente 2 intentos (primario + 1 fallback), sin loop.
    assert llamadas == ["gpt-4o-mini", "claude-haiku-4-5"]
