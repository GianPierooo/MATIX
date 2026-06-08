"""Optimizaciones de latencia del chat: clasificador rápido pre-LLM + tool
calls en paralelo dentro del loop.

Cubre:
- Saludos y "anota X" se resuelven sin tocar `llm.responder_con_tools`.
- "crea tarea X" sin fecha llama directo a `ejecutar_tool` (un solo round-trip).
- Cuando el modelo pide varias tools en una vuelta, se ejecutan EN PARALELO
  (no en serie).
- Mensajes con imagen o documento NUNCA toman la ruta rápida.
"""
from __future__ import annotations

import asyncio

from app.matix import chat as chat_mod


# Stubs livianos (mismo patrón que test_chat_modelo.py).


async def _sin_contexto(db):
    return ""


async def _sin_memoria(db):
    return ""


async def _sin_modo(db):
    return None


def _stub_contexto(monkeypatch):
    monkeypatch.setattr(chat_mod, "contexto_vivo", _sin_contexto)
    monkeypatch.setattr(chat_mod.memoria, "bloque_memoria", _sin_memoria)
    monkeypatch.setattr(chat_mod.modos, "modo_activo", _sin_modo)

    async def sel(db):
        return "gpt-4o-mini"

    monkeypatch.setattr(chat_mod.modelos_llm, "seleccion_guardada", sel)


# ── Saludo: cero llamadas al LLM, cero a la BD ──────────────────────────────


async def test_saludo_no_llama_al_llm(monkeypatch):
    _stub_contexto(monkeypatch)
    llamadas_llm: list = []

    async def fake_resp(*args, **kwargs):
        llamadas_llm.append(1)
        return {"tipo": "texto", "contenido": "no debí ser llamado", "raw": {}}

    monkeypatch.setattr(chat_mod.llm, "responder_con_tools", fake_resp)

    r = await chat_mod.conversar(
        None, historial=[], mensaje="hola", persistir=False
    )
    assert r["respuesta"]  # respuesta plantilla peruana
    assert r["tools_usadas"] == []
    assert r["tablas_cambiadas"] == []
    assert llamadas_llm == []  # el LLM NO se llamó


# ── "Anota X" → ejecuta crear_apunte SIN LLM ────────────────────────────────


async def test_anota_ejecuta_crear_apunte_sin_llm(monkeypatch):
    _stub_contexto(monkeypatch)
    llamadas_llm: list = []
    llamadas_tool: list = []

    async def fake_resp(*args, **kwargs):
        llamadas_llm.append(1)
        return {"tipo": "texto", "contenido": "x", "raw": {}}

    async def fake_tool(db, nombre, args, *, conversacion_id=None):
        llamadas_tool.append({"nombre": nombre, "args": args})
        return {"ok": True, "datos": {"id": "abc", "titulo": args.get("titulo", "")}}

    monkeypatch.setattr(chat_mod.llm, "responder_con_tools", fake_resp)
    monkeypatch.setattr(chat_mod, "ejecutar_tool", fake_tool)

    r = await chat_mod.conversar(
        None, historial=[], mensaje="anota: la idea del bot de bolsa", persistir=False
    )
    assert r["tools_usadas"] == ["crear_apunte"]
    assert "apuntes" in r["tablas_cambiadas"]
    assert "idea" in (llamadas_tool[0]["args"]["titulo"])
    assert llamadas_llm == []  # NO se llamó al LLM


async def test_crea_tarea_simple_sin_fecha_evita_el_llm(monkeypatch):
    _stub_contexto(monkeypatch)
    llamadas_llm: list = []
    llamadas_tool: list = []

    async def fake_resp(*args, **kwargs):
        llamadas_llm.append(1)
        return {"tipo": "texto", "contenido": "x", "raw": {}}

    async def fake_tool(db, nombre, args, *, conversacion_id=None):
        llamadas_tool.append({"nombre": nombre, "args": args})
        return {"ok": True, "datos": {"id": "abc", "titulo": args["titulo"]}}

    monkeypatch.setattr(chat_mod.llm, "responder_con_tools", fake_resp)
    monkeypatch.setattr(chat_mod, "ejecutar_tool", fake_tool)

    r = await chat_mod.conversar(
        None, historial=[], mensaje="crea una tarea de pasear al perro", persistir=False
    )
    assert llamadas_llm == []
    assert llamadas_tool[0]["nombre"] == "crear_tarea"
    assert "pasear al perro" in r["respuesta"]


# ── Con imagen NUNCA atajo: el modelo TIENE que verla ───────────────────────


async def test_imagen_adjunta_fuerza_camino_llm(monkeypatch):
    _stub_contexto(monkeypatch)
    llamadas_llm: list = []

    async def fake_resp(*args, **kwargs):
        llamadas_llm.append(1)
        return {"tipo": "texto", "contenido": "visto", "raw": {"role": "assistant", "content": "visto"}}

    monkeypatch.setattr(chat_mod.llm, "responder_con_tools", fake_resp)

    r = await chat_mod.conversar(
        None,
        historial=[],
        mensaje="anota: lo que ves",
        imagen="data:image/jpeg;base64,uno",
        persistir=False,
    )
    assert llamadas_llm == [1]  # el LLM SÍ se llamó
    assert r["respuesta"] == "visto"


# ── Tool calls EN PARALELO dentro de una vuelta ─────────────────────────────


async def test_tool_calls_se_ejecutan_en_paralelo(monkeypatch):
    """Cuando el modelo pide varias tools en una sola vuelta, antes corrían en
    serie (round-trips a la BD acumulados). Ahora deben dispararse junto vía
    asyncio.gather. Probamos con dos tools "lentas" (200ms cada una): en serie
    sumarían ~400ms; en paralelo ~200ms. Margen amplio para que el test no sea
    flaky en CI."""
    _stub_contexto(monkeypatch)

    # Primera vuelta: el modelo pide DOS tools.
    # Segunda vuelta: cierra con texto.
    vuelta = {"n": 0}

    async def fake_resp(messages, tools, *, model=None, temperature=0.6, tool_choice="auto"):
        vuelta["n"] += 1
        if vuelta["n"] == 1:
            return {
                "tipo": "tool_calls",
                "tool_calls": [
                    {"id": "call_a", "nombre": "consultar_tareas", "args": {}},
                    {"id": "call_b", "nombre": "consultar_eventos", "args": {}},
                ],
                "raw": {"role": "assistant", "content": ""},
            }
        return {"tipo": "texto", "contenido": "ya", "raw": {"role": "assistant", "content": "ya"}}

    inicios: list[float] = []

    async def fake_tool_lento(db, nombre, args, *, conversacion_id=None):
        # Cada tool tarda 200ms. Si corren en serie, total ≥ 400ms; en paralelo
        # debería rondar 200ms.
        inicios.append(asyncio.get_event_loop().time())
        await asyncio.sleep(0.2)
        return {"ok": True, "datos": {}}

    monkeypatch.setattr(chat_mod.llm, "responder_con_tools", fake_resp)
    monkeypatch.setattr(chat_mod, "ejecutar_tool", fake_tool_lento)

    import time
    t0 = time.monotonic()
    r = await chat_mod.conversar(
        None, historial=[], mensaje="qué tengo hoy?", persistir=False
    )
    dt = time.monotonic() - t0

    assert r["respuesta"] == "ya"
    assert len(inicios) == 2
    # En paralelo: ambos tools arrancan casi al mismo tiempo (delta < 50ms).
    assert abs(inicios[1] - inicios[0]) < 0.05
    # Y el total se acerca a 200ms, no a 400ms. Damos margen al overhead del
    # test runner.
    assert dt < 0.35, f"tools en serie ({dt:.3f}s ≥ 0.35s) — falló paralelización"
