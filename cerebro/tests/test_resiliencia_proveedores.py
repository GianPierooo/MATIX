"""Resiliencia multi-proveedor de IA (failover + proveedor preferido + cadenas).

Tests PUROS: se monkeypatchean los intentos por-proveedor; no hay red ni keys.
Cubren la ruta de failover (un proveedor cae → el otro responde), incluido el
caso clave del usuario (sin crédito de OpenAI → 401/quota → cae a Claude), el
proveedor preferido, la cadena de TTS, embeddings degradados y el medidor.
"""
from __future__ import annotations

import pytest

from app.matix import llm, modelos_llm
from app.matix.uso import MedidorUso


class _ErrAuth(Exception):
    status_code = 401


class _ErrQuota(Exception):
    status_code = 429

    def __str__(self) -> str:
        return "Error code: 429 - insufficient_quota: you exceeded your current quota"


class _ErrTransitorio(Exception):
    status_code = 503


class _ErrLegitimo(Exception):
    status_code = 400


# ── Clasificador ─────────────────────────────────────────────────────────────


def test_clasificador_auth_y_credito():
    assert llm._es_auth_o_credito(_ErrAuth()) is True
    assert llm._es_auth_o_credito(_ErrQuota()) is True
    assert llm._es_auth_o_credito(_ErrLegitimo()) is False


def test_amerita_failover():
    assert llm._amerita_failover(_ErrAuth()) is True       # NUEVO: auth cae al otro
    assert llm._amerita_failover(_ErrQuota()) is True       # sin crédito → cae
    assert llm._amerita_failover(_ErrTransitorio()) is True  # 5xx → cae
    assert llm._amerita_failover(_ErrLegitimo()) is False    # 400 → NO


# ── Proveedor preferido ──────────────────────────────────────────────────────


def test_modelo_efectivo_respeta_preferido(monkeypatch):
    monkeypatch.setattr(modelos_llm, "proveedor_preferido", lambda: "anthropic")
    eff = llm._modelo_efectivo("gpt-4o-mini")
    assert modelos_llm.proveedor_de_id(eff) == "anthropic"

    monkeypatch.setattr(modelos_llm, "proveedor_preferido", lambda: "openai")
    eff = llm._modelo_efectivo("claude-haiku-4-5")
    assert modelos_llm.proveedor_de_id(eff) == "openai"

    monkeypatch.setattr(modelos_llm, "proveedor_preferido", lambda: "auto")
    assert llm._modelo_efectivo("gpt-4o-mini") == "gpt-4o-mini"


# ── Failover de chat (con tools) ─────────────────────────────────────────────


async def test_failover_chat_por_credito_cae_a_claude(monkeypatch):
    monkeypatch.setattr(modelos_llm, "proveedor_preferido", lambda: "auto")
    vistos: list[str] = []

    async def fake(model, messages, tools, *, temperature, tool_choice):
        vistos.append(model)
        if modelos_llm.proveedor_de_id(model) == "openai":
            raise _ErrQuota()
        return {"tipo": "texto", "contenido": "hola desde claude", "raw": {}}

    monkeypatch.setattr(llm, "_con_tools_en", fake)
    res = await llm.responder_con_tools([{"role": "user", "content": "hi"}], [], model="gpt-4o-mini")
    assert res["failover"] is True
    assert modelos_llm.proveedor_de_id(res["modelo_efectivo"]) == "anthropic"
    assert res["contenido"] == "hola desde claude"
    assert modelos_llm.proveedor_de_id(vistos[0]) == "openai"  # intentó OpenAI primero


async def test_failover_chat_por_auth(monkeypatch):
    monkeypatch.setattr(modelos_llm, "proveedor_preferido", lambda: "auto")

    async def fake(model, messages, tools, *, temperature, tool_choice):
        if modelos_llm.proveedor_de_id(model) == "openai":
            raise _ErrAuth()
        return {"tipo": "texto", "contenido": "ok", "raw": {}}

    monkeypatch.setattr(llm, "_con_tools_en", fake)
    res = await llm.responder_con_tools([{"role": "user", "content": "hi"}], [], model="gpt-4o-mini")
    assert res["failover"] is True


async def test_no_failover_en_error_legitimo(monkeypatch):
    monkeypatch.setattr(modelos_llm, "proveedor_preferido", lambda: "auto")

    async def fake(model, messages, tools, *, temperature, tool_choice):
        raise _ErrLegitimo()

    monkeypatch.setattr(llm, "_con_tools_en", fake)
    with pytest.raises(_ErrLegitimo):
        await llm.responder_con_tools([{"role": "user", "content": "hi"}], [], model="gpt-4o-mini")


async def test_preferido_anthropic_intenta_claude_primero(monkeypatch):
    monkeypatch.setattr(modelos_llm, "proveedor_preferido", lambda: "anthropic")
    vistos: list[str] = []

    async def fake(model, messages, tools, *, temperature, tool_choice):
        vistos.append(model)
        return {"tipo": "texto", "contenido": "ok", "raw": {}}

    monkeypatch.setattr(llm, "_con_tools_en", fake)
    await llm.responder_con_tools([{"role": "user", "content": "hi"}], [], model="gpt-4o-mini")
    assert modelos_llm.proveedor_de_id(vistos[0]) == "anthropic"  # preferido primero


# ── Visión (cámara) con failover ─────────────────────────────────────────────


async def test_narrar_frame_failover_a_claude(monkeypatch):
    monkeypatch.setattr(modelos_llm, "proveedor_preferido", lambda: "auto")

    async def fake_vision(model, system, pedido, imagen, *, max_tokens):
        if modelos_llm.proveedor_de_id(model) == "openai":
            raise _ErrAuth()
        return "veo un escritorio con una laptop"

    monkeypatch.setattr(llm, "_vision_en", fake_vision)
    out = await llm.narrar_frame("data:image/jpeg;base64,xxx")
    assert out == "veo un escritorio con una laptop"


# ── TTS: cadena ElevenLabs → OpenAI ──────────────────────────────────────────


async def test_tts_sin_eleven_usa_openai(monkeypatch):
    monkeypatch.setattr(llm.settings, "elevenlabs_api_key", "")

    async def fake_openai(texto, voz, model, formato):
        return b"AUDIO_OPENAI"

    monkeypatch.setattr(llm, "_openai_tts", fake_openai)
    audio, prov = await llm.hablar("hola")
    assert audio == b"AUDIO_OPENAI"
    assert prov == "openai"


async def test_tts_con_eleven_usa_eleven(monkeypatch):
    monkeypatch.setattr(llm.settings, "elevenlabs_api_key", "k")

    async def fake_eleven(texto, formato):
        return b"AUDIO_ELEVEN"

    monkeypatch.setattr(llm, "_eleven_tts", fake_eleven)
    audio, prov = await llm.hablar("hola")
    assert prov == "elevenlabs"


async def test_tts_eleven_cae_a_openai(monkeypatch):
    monkeypatch.setattr(llm.settings, "elevenlabs_api_key", "k")

    async def eleven_falla(texto, formato):
        raise _ErrTransitorio()

    async def fake_openai(texto, voz, model, formato):
        return b"AUDIO_OPENAI"

    monkeypatch.setattr(llm, "_eleven_tts", eleven_falla)
    monkeypatch.setattr(llm, "_openai_tts", fake_openai)
    audio, prov = await llm.hablar("hola")
    assert prov == "openai"  # ElevenLabs cayó → OpenAI


async def test_tts_todo_cae_levanta_runtime(monkeypatch):
    monkeypatch.setattr(llm.settings, "elevenlabs_api_key", "")

    async def openai_falla(texto, voz, model, formato):
        raise _ErrTransitorio()

    monkeypatch.setattr(llm, "_openai_tts", openai_falla)
    with pytest.raises(RuntimeError):
        await llm.hablar("hola")  # la app cae a la voz del dispositivo


# ── Embeddings degradados ────────────────────────────────────────────────────


async def test_embebir_seguro_none_en_error(monkeypatch):
    async def boom(textos):
        raise _ErrAuth()

    monkeypatch.setattr(llm, "embebir", boom)
    assert await llm.embebir_seguro(["x"]) is None


async def test_embebir_seguro_ok(monkeypatch):
    async def fake(textos):
        return [[0.1, 0.2]]

    monkeypatch.setattr(llm, "embebir", fake)
    assert await llm.embebir_seguro(["x"]) == [[0.1, 0.2]]


# ── Medidor etiqueta proveedor ───────────────────────────────────────────────


def test_medidor_por_proveedor():
    m = MedidorUso()
    m.registrar_chat({"prompt_tokens": 100, "completion_tokens": 50}, proveedor="anthropic")
    m.registrar_chat({"prompt_tokens": 10, "completion_tokens": 5}, proveedor="openai")
    snap = m.snapshot()
    assert snap["por_proveedor"]["anthropic"]["llamadas"] == 1
    assert snap["por_proveedor"]["openai"]["llamadas"] == 1
    assert snap["por_proveedor"]["anthropic"]["costo_usd"] >= 0
