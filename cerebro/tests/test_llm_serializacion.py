"""Serialización por proveedor de la conversación NEUTRA (con tool calls y
results) + mapa de capacidades por modelo. Puro, sin red ni API keys."""
from __future__ import annotations

import json

from app.matix import llm, modelos_llm


def _historia_neutra():
    """Historia con un assistant NEUTRO que llamó una tool + su resultado."""
    return [
        {"role": "system", "content": "Eres Matix."},
        {"role": "user", "content": "crea una tarea"},
        {
            "role": "assistant",
            "contenido": "",
            "tool_calls": [{"id": "c1", "nombre": "crear_tarea", "args": {"titulo": "X"}}],
        },
        {"role": "tool", "tool_call_id": "c1", "content": "{\"ok\": true}"},
        {"role": "user", "content": "gracias"},
    ]


def test_a_openai_serializa_tool_calls_y_results():
    out = llm._a_openai(_historia_neutra())
    asis = next(m for m in out if m["role"] == "assistant")
    assert asis["tool_calls"][0]["id"] == "c1"
    assert asis["tool_calls"][0]["type"] == "function"
    assert asis["tool_calls"][0]["function"]["name"] == "crear_tarea"
    # arguments es string JSON
    assert json.loads(asis["tool_calls"][0]["function"]["arguments"]) == {"titulo": "X"}
    # el tool result mantiene su tool_call_id (matchea el id de arriba)
    tool = next(m for m in out if m["role"] == "tool")
    assert tool["tool_call_id"] == "c1"
    # NUNCA aparece un bloque 'tool_use' (eso es de Anthropic) en OpenAI
    assert "tool_use" not in json.dumps(out)


def test_a_anthropic_serializa_tool_use_y_tool_result():
    system, msgs = llm._a_anthropic(_historia_neutra())
    assert "Matix" in system
    # assistant → bloque tool_use con el mismo id
    asis = next(m for m in msgs if m["role"] == "assistant")
    bloque = asis["content"][0]
    assert bloque["type"] == "tool_use" and bloque["id"] == "c1"
    assert bloque["name"] == "crear_tarea" and bloque["input"] == {"titulo": "X"}
    # el tool result va en un user con tool_result del MISMO id
    user_tr = next(
        m for m in msgs
        if m["role"] == "user" and isinstance(m["content"], list)
        and m["content"][0].get("type") == "tool_result"
    )
    assert user_tr["content"][0]["tool_use_id"] == "c1"
    # NUNCA aparece 'tool_calls' estilo OpenAI en Anthropic
    assert "tool_calls" not in json.dumps(msgs)


def test_misma_historia_neutra_va_a_ambos_proveedores():
    """El núcleo del fix P2: la MISMA representación neutra serializa bien a los
    dos proveedores (failover a mitad de turno no rompe)."""
    h = _historia_neutra()
    op = llm._a_openai(h)
    _, an = llm._a_anthropic(h)
    assert op and an  # ambas válidas, sin filtrar bloques crudos del otro


def test_assistant_solo_texto():
    h = [{"role": "assistant", "contenido": "hola", "tool_calls": []}]
    op = llm._a_openai(h)
    assert op[0] == {"role": "assistant", "content": "hola"}
    _, an = llm._a_anthropic(h)
    assert an[0]["content"] == "hola" or an[0]["content"][0]["text"] == "hola"


def test_soporta_temperature_por_modelo():
    # Razonadores GPT-5 / o-series: NO soportan temperature custom.
    assert modelos_llm.soporta_temperature("gpt-5.5") is False
    assert modelos_llm.soporta_temperature("gpt-5.4-mini") is False
    assert modelos_llm.soporta_temperature("o3") is False
    # Estos sí.
    assert modelos_llm.soporta_temperature("gpt-4o-mini") is True
    assert modelos_llm.soporta_temperature("claude-sonnet-4-6") is True
