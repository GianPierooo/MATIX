"""El dispatcher de tools nunca propaga: ante un fallo devuelve un
`_error` estructurado. Tras el incidente del device ("HTTPStatusError"
opaco al crear apuntes/tareas con la BD sin la migración aplicada),
queremos que:

- un fallo de PostgREST (httpx.HTTPStatusError) surface el CÓDIGO HTTP en
  el mensaje (ej. "HTTP 404"), no solo el nombre de la clase.
- cualquier otro error nombre su tipo.

(El status + cuerpo real se loguean para verlos en Railway; eso no se
testea acá, pero el mensaje sí.)
"""
from __future__ import annotations

import httpx

from app.matix import tools


async def test_http_status_error_surface_codigo(monkeypatch):
    async def boom(db, args):  # noqa: ANN001, ARG001
        raise httpx.HTTPStatusError(
            "x",
            request=httpx.Request("POST", "http://t"),
            response=httpx.Response(404, text='{"code":"PGRST205"}'),
        )

    monkeypatch.setitem(tools._HANDLERS, "_test_boom_http", boom)
    r = await tools.ejecutar_tool(None, "_test_boom_http", {})
    assert r["ok"] is False
    assert "HTTP 404" in r["mensaje"]


async def test_otro_error_nombra_el_tipo(monkeypatch):
    async def boom(db, args):  # noqa: ANN001, ARG001
        raise ValueError("nope")

    monkeypatch.setitem(tools._HANDLERS, "_test_boom_val", boom)
    r = await tools.ejecutar_tool(None, "_test_boom_val", {})
    assert r["ok"] is False
    assert "ValueError" in r["mensaje"]


async def test_tool_desconocida():
    r = await tools.ejecutar_tool(None, "no_existe_esta_tool", {})
    assert r["ok"] is False
