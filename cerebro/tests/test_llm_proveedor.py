"""Tests de la capa de proveedor del LLM de chat (OpenAI ↔ Anthropic).

NO pegamos a ninguna API: mockeamos los clientes (`_get_openai_client` /
`_get_anthropic_client`) y verificamos:
- la traducción de mensajes/tools/visión al formato de cada proveedor,
- el parseo de tool calls / texto a la forma NEUTRA que consume `chat.py`,
- la selección de proveedor por env y el modo JSON de ambos.
"""
from __future__ import annotations

import types

import pytest

from app.matix import llm


# ── Fakes ───────────────────────────────────────────────────────────


def _openai_resp(*, content=None, tool_calls=None):
    msg = types.SimpleNamespace(
        content=content,
        tool_calls=tool_calls,
        model_dump=lambda exclude_none=False: {"role": "assistant", "content": content},
    )
    return types.SimpleNamespace(
        choices=[types.SimpleNamespace(message=msg)],
        usage={"prompt_tokens": 10, "completion_tokens": 5},
    )


def _fake_openai(resp, capture):
    async def create(**kw):
        capture.update(kw)
        return resp

    return types.SimpleNamespace(
        chat=types.SimpleNamespace(completions=types.SimpleNamespace(create=create))
    )


def _anth_block(**kw):
    return types.SimpleNamespace(
        type=kw.get("type"),
        text=kw.get("text", ""),
        id=kw.get("id"),
        name=kw.get("name"),
        input=kw.get("input"),
        model_dump=lambda: dict(kw),
    )


def _anth_resp(content):
    return types.SimpleNamespace(
        content=content,
        usage=types.SimpleNamespace(
            input_tokens=10, output_tokens=5, cache_read_input_tokens=0
        ),
    )


def _fake_anthropic(resp, capture):
    async def create(**kw):
        capture.update(kw)
        return resp

    return types.SimpleNamespace(messages=types.SimpleNamespace(create=create))


# ── Traducción de mensajes a Anthropic (puro) ───────────────────────


def test_a_anthropic_saca_system_y_agrupa_tool_results():
    msgs = [
        {"role": "system", "content": "reglas"},
        {"role": "system", "content": "contexto"},
        {"role": "user", "content": "hola"},
        {"role": "assistant", "content": [{"type": "tool_use", "id": "t1", "name": "x", "input": {}}]},
        {"role": "tool", "tool_call_id": "t1", "content": "ok"},
        {"role": "tool", "tool_call_id": "t2", "content": "ok2"},
    ]
    system, out = llm._a_anthropic(msgs)
    assert system == "reglas\n\ncontexto"
    # user, assistant(tool_use), user(tool_results agrupados)
    assert [m["role"] for m in out] == ["user", "assistant", "user"]
    # El assistant con content lista (raw) pasa tal cual.
    assert out[1]["content"][0]["type"] == "tool_use"
    # Los dos tool_result quedan en UN solo mensaje user.
    bloques = out[2]["content"]
    assert len(bloques) == 2
    assert bloques[0]["type"] == "tool_result"
    assert bloques[0]["tool_use_id"] == "t1"


def test_a_anthropic_traduce_imagen_multimodal():
    msgs = [
        {
            "role": "user",
            "content": [
                {"type": "text", "text": "mira"},
                {"type": "image_url", "image_url": {"url": "data:image/png;base64,AAAA"}},
            ],
        }
    ]
    _, out = llm._a_anthropic(msgs)
    bloques = out[0]["content"]
    assert bloques[0] == {"type": "text", "text": "mira"}
    assert bloques[1]["type"] == "image"
    assert bloques[1]["source"]["media_type"] == "image/png"
    assert bloques[1]["source"]["data"] == "AAAA"


def test_tools_y_tool_choice_a_anthropic():
    tools = [
        {"type": "function", "function": {"name": "crear_tarea", "description": "d", "parameters": {"type": "object"}}}
    ]
    a = llm._tools_a_anthropic(tools)
    assert a == [{"name": "crear_tarea", "description": "d", "input_schema": {"type": "object"}}]
    assert llm._tool_choice_a_anthropic("auto") == {"type": "auto"}
    assert llm._tool_choice_a_anthropic(
        {"type": "function", "function": {"name": "crear_apunte"}}
    ) == {"type": "tool", "name": "crear_apunte"}


# ── OpenAI: parseo de tool calls + texto ────────────────────────────


async def test_openai_con_tools_parsea_tool_calls(monkeypatch):
    tc = types.SimpleNamespace(
        id="call_1",
        function=types.SimpleNamespace(name="crear_tarea", arguments='{"titulo": "x"}'),
    )
    cap: dict = {}
    monkeypatch.setattr(llm, "_get_openai_client", lambda: _fake_openai(_openai_resp(tool_calls=[tc]), cap))
    out = await llm._openai_con_tools([], [], model="gpt-4o-mini", temperature=0.6, tool_choice="auto")
    assert out["tipo"] == "tool_calls"
    assert out["tool_calls"][0] == {"id": "call_1", "nombre": "crear_tarea", "args": {"titulo": "x"}}


async def test_openai_json_devuelve_contenido(monkeypatch):
    cap: dict = {}
    monkeypatch.setattr(llm, "_get_openai_client", lambda: _fake_openai(_openai_resp(content='{"ok": 1}'), cap))
    s = await llm._openai_json([{"role": "user", "content": "x"}], model="gpt-4o-mini", temperature=0)
    assert s == '{"ok": 1}'
    assert cap["response_format"] == {"type": "json_object"}


# ── Anthropic: parseo de tool use + texto + JSON por prefill ────────


async def test_anthropic_con_tools_parsea_tool_use(monkeypatch):
    resp = _anth_resp([_anth_block(type="tool_use", id="tu1", name="crear_tarea", input={"titulo": "x"})])
    cap: dict = {}
    monkeypatch.setattr(llm, "_get_anthropic_client", lambda: _fake_anthropic(resp, cap))
    out = await llm._anthropic_con_tools(
        [{"role": "system", "content": "s"}, {"role": "user", "content": "haz x"}],
        [{"type": "function", "function": {"name": "crear_tarea", "parameters": {}}}],
        model="claude-x",
        temperature=0.6,
        tool_choice="auto",
    )
    assert out["tipo"] == "tool_calls"
    assert out["tool_calls"][0] == {"id": "tu1", "nombre": "crear_tarea", "args": {"titulo": "x"}}
    # El system salió aparte. Va envuelto con cache_control (prompt caching de
    # Anthropic): el texto está dentro del bloque.
    assert cap["system"][0]["text"] == "s"
    assert cap["system"][0]["cache_control"] == {"type": "ephemeral"}
    assert cap["tool_choice"] == {"type": "auto"}
    # `raw` re-inyectable como assistant con bloques.
    assert out["raw"]["role"] == "assistant"


async def test_anthropic_con_tools_texto(monkeypatch):
    resp = _anth_resp([_anth_block(type="text", text="hola señor")])
    monkeypatch.setattr(llm, "_get_anthropic_client", lambda: _fake_anthropic(resp, {}))
    out = await llm._anthropic_con_tools([{"role": "user", "content": "hi"}], [], model="claude-x", temperature=0.6, tool_choice="auto")
    assert out["tipo"] == "texto"
    assert out["contenido"] == "hola señor"


async def test_anthropic_json_usa_prefill(monkeypatch):
    resp = _anth_resp([_anth_block(type="text", text='"ok": 1}')])
    cap: dict = {}
    monkeypatch.setattr(llm, "_get_anthropic_client", lambda: _fake_anthropic(resp, cap))
    s = await llm._anthropic_json([{"role": "user", "content": "x"}], model="claude-x", temperature=0)
    assert s == '{"ok": 1}'  # prefill "{" + continuación
    # El último mensaje es el prefill assistant "{".
    assert cap["messages"][-1] == {"role": "assistant", "content": "{"}


# ── Ruteo por ID del modelo (no por env) ────────────────────────────


async def test_dispatch_se_infiere_del_id_del_modelo(monkeypatch):
    # id gpt-* → OpenAI
    monkeypatch.setattr(llm, "_get_openai_client", lambda: _fake_openai(_openai_resp(content="oai"), {}))
    out = await llm.responder_con_tools([], [], model="gpt-4o-mini")
    assert out["contenido"] == "oai"

    # id claude-* → Anthropic (sin tocar ninguna env var)
    monkeypatch.setattr(llm, "_get_anthropic_client", lambda: _fake_anthropic(_anth_resp([_anth_block(type="text", text="claude")]), {}))
    out2 = await llm.responder_con_tools([{"role": "user", "content": "x"}], [], model="claude-opus-4-8")
    assert out2["contenido"] == "claude"


def test_es_anthropic_por_id():
    assert llm._es_anthropic("claude-opus-4-8") is True
    assert llm._es_anthropic("claude-sonnet-4-6") is True
    assert llm._es_anthropic("gpt-5.5") is False
    assert llm._es_anthropic("gpt-4o-mini") is False
    assert llm._es_anthropic("o3") is False


def test_modelo_chat_resuelve_env(monkeypatch):
    monkeypatch.setattr(llm.settings, "matix_llm_model", "claude-opus-4-8")
    assert llm._modelo_chat(None) == "claude-opus-4-8"
    assert llm._modelo_chat("explicito") == "explicito"
