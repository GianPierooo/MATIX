"""Búsqueda web (tool `buscar_web`) — Tavily mockeado, sin red ni key real."""
from __future__ import annotations

import pytest

from app.matix import busqueda_web as bw
from app.matix import tools

# Respuesta cruda típica de Tavily (recortada a lo que usamos).
_FAKE_TAVILY = {
    "results": [
        {
            "title": "Título uno",
            "url": "https://ejemplo.com/uno",
            "content": "Extracto de la fuente uno con info relevante.",
        },
        {
            "title": "Título dos",
            "url": "https://ejemplo.com/dos",
            "content": "x" * 800,  # supera MAX_EXTRACTO → se trunca
        },
        {
            "title": "Sin url (se descarta)",
            "url": "",
            "content": "no debería aparecer",
        },
    ]
}


def test_limpiar_formatea_y_trunca():
    fuentes = bw._limpiar(_FAKE_TAVILY)
    # La fuente sin url se descarta.
    assert len(fuentes) == 2
    assert fuentes[0] == {
        "titulo": "Título uno",
        "url": "https://ejemplo.com/uno",
        "extracto": "Extracto de la fuente uno con info relevante.",
    }
    # El extracto largo se trunca con elipsis.
    assert len(fuentes[1]["extracto"]) <= bw.MAX_EXTRACTO + 1
    assert fuentes[1]["extracto"].endswith("…")


@pytest.mark.asyncio
async def test_buscar_sin_key_lanza(monkeypatch):
    monkeypatch.delenv("TAVILY_API_KEY", raising=False)
    with pytest.raises(bw.BusquedaWebError):
        await bw.buscar("clima en Lima")


@pytest.mark.asyncio
async def test_buscar_consulta_vacia_lanza(monkeypatch):
    monkeypatch.setenv("TAVILY_API_KEY", "k-test")
    with pytest.raises(bw.BusquedaWebError):
        await bw.buscar("   ")


@pytest.mark.asyncio
async def test_buscar_ok(monkeypatch):
    monkeypatch.setenv("TAVILY_API_KEY", "k-test")
    llamadas = {}

    def fake(api_key, consulta, n):
        llamadas["api_key"] = api_key
        llamadas["consulta"] = consulta
        llamadas["n"] = n
        return _FAKE_TAVILY

    monkeypatch.setattr(bw, "_tavily_search", fake)
    fuentes = await bw.buscar("últimas noticias IA")
    assert [f["url"] for f in fuentes] == [
        "https://ejemplo.com/uno",
        "https://ejemplo.com/dos",
    ]
    assert llamadas["consulta"] == "últimas noticias IA"
    assert llamadas["n"] == bw.MAX_RESULTADOS


@pytest.mark.asyncio
async def test_buscar_tavily_falla_lanza(monkeypatch):
    monkeypatch.setenv("TAVILY_API_KEY", "k-test")

    def fake(api_key, consulta, n):
        raise RuntimeError("rate limit")

    monkeypatch.setattr(bw, "_tavily_search", fake)
    with pytest.raises(bw.BusquedaWebError):
        await bw.buscar("algo")


# ── La tool a través del dispatcher ─────────────────────────────────


@pytest.mark.asyncio
async def test_tool_buscar_web_ok(monkeypatch):
    async def fake_buscar(consulta, **kw):
        return [{"titulo": "T", "url": "https://x.com", "extracto": "e"}]

    monkeypatch.setattr(bw, "buscar", fake_buscar)
    res = await tools.ejecutar_tool(None, "buscar_web", {"consulta": "precio del oro"})
    assert res["ok"] is True
    assert res["datos"]["fuentes"][0]["url"] == "https://x.com"
    assert "instruccion" in res["datos"]


@pytest.mark.asyncio
async def test_tool_buscar_web_sin_consulta():
    res = await tools.ejecutar_tool(None, "buscar_web", {})
    assert res["ok"] is False
    assert res["tipo"] == "validacion"


@pytest.mark.asyncio
async def test_tool_buscar_web_error_amable(monkeypatch):
    async def fake_buscar(consulta, **kw):
        raise bw.BusquedaWebError("sin key")

    monkeypatch.setattr(bw, "buscar", fake_buscar)
    res = await tools.ejecutar_tool(None, "buscar_web", {"consulta": "x"})
    assert res["ok"] is False
    assert res["tipo"] == "busqueda_web"
    assert "no pude buscar" in res["mensaje"].lower()


@pytest.mark.asyncio
async def test_tool_buscar_web_sin_resultados(monkeypatch):
    async def fake_buscar(consulta, **kw):
        return []

    monkeypatch.setattr(bw, "buscar", fake_buscar)
    res = await tools.ejecutar_tool(None, "buscar_web", {"consulta": "x"})
    assert res["ok"] is True
    assert res["datos"]["fuentes"] == []


def test_buscar_web_en_definiciones_y_handlers():
    nombres = {t["function"]["name"] for t in tools.TOOL_DEFINITIONS}
    assert "buscar_web" in nombres
    assert "buscar_web" in tools._HANDLERS
    assert tools.TABLAS_AFECTADAS["buscar_web"] == []
