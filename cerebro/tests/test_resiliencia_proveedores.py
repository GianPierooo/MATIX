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


class _ErrCreditoAnthropic(Exception):
    """Crédito agotado de Anthropic: viene como 400 (no 429), con el mensaje
    «your credit balance is too low». Este es el que tumbaba el chat."""

    status_code = 400

    def __str__(self) -> str:
        return (
            "Error code: 400 - {'type': 'error', 'error': {'type': "
            "'invalid_request_error', 'message': 'Your credit balance is too low "
            "to access the Anthropic API. Please go to Plans & Billing...'}}"
        )


# ── Clasificador ─────────────────────────────────────────────────────────────


def test_clasificador_auth_y_credito():
    assert llm._es_auth_o_credito(_ErrAuth()) is True
    assert llm._es_auth_o_credito(_ErrQuota()) is True
    assert llm._es_auth_o_credito(_ErrLegitimo()) is False


def test_credito_anthropic_400_amerita_failover():
    """Regresión: el crédito agotado de Anthropic llega como 400 (no 429). Antes
    NO disparaba failover y el turno moría con «Error del cerebro»; ahora sí
    cruza al otro proveedor (a un GPT fuerte)."""
    e = _ErrCreditoAnthropic()
    assert llm._es_auth_o_credito(e) is True
    assert llm._amerita_failover(e) is True
    # Y el modelo de failover de un Claude fuerte es un GPT fuerte (no mini).
    assert modelos_llm.modelo_fallback("claude-sonnet-4-6") == "gpt-5.5"


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


def test_timeout_amerita_failover():
    # Un `asyncio.wait_for` agotado lanza `TimeoutError`: debe contarse como
    # transitorio (cuelga el proveedor) y ameritar failover.
    import asyncio
    assert llm._es_error_de_proveedor(asyncio.TimeoutError()) is True
    assert llm._amerita_failover(TimeoutError()) is True


async def test_narrar_frame_timeout_primario_cae_al_otro(monkeypatch):
    # El primario CUELGA (más que el timeout agresivo) → no congela la cámara:
    # se corta y cae al otro proveedor al instante (preferencia 'auto').
    import asyncio
    monkeypatch.setattr(modelos_llm, "proveedor_preferido", lambda: "auto")
    monkeypatch.setattr(llm, "_NARRACION_TIMEOUT_S", 0.05)

    async def fake_vision(model, system, pedido, imagen, *, max_tokens):
        if modelos_llm.proveedor_de_id(model) == "openai":
            await asyncio.sleep(1)  # cuelga: supera el timeout agresivo
            return "no debería llegar"
        return "ahora veo a Claude respondiendo rápido"

    monkeypatch.setattr(llm, "_vision_en", fake_vision)
    out = await llm.narrar_frame("data:image/jpeg;base64,xxx")
    assert out == "ahora veo a Claude respondiendo rápido"


async def test_narrar_frame_pinned_no_cruza_de_proveedor(monkeypatch):
    # Si el usuario FIJÓ un proveedor (Claude), un fallo NO debe cruzar a OpenAI:
    # se respeta la preferencia y el frame queda sin frase (la cámara sigue).
    monkeypatch.setattr(modelos_llm, "proveedor_preferido", lambda: "anthropic")
    vistos: list[str] = []

    async def fake_vision(model, system, pedido, imagen, *, max_tokens):
        vistos.append(model)
        raise _ErrTransitorio()  # incluso un 5xx: NO cruzamos cuando está pinneado

    monkeypatch.setattr(llm, "_vision_en", fake_vision)
    out = await llm.narrar_frame("data:image/jpeg;base64,xxx")
    assert out == ""  # degradó sin frase
    assert vistos, "debió intentar el proveedor preferido"
    assert all(modelos_llm.proveedor_de_id(m) == "anthropic" for m in vistos)
    assert not any(modelos_llm.proveedor_de_id(m) == "openai" for m in vistos)


async def test_narrar_frame_pinned_ok_no_toca_el_otro(monkeypatch):
    # Pinneado a Claude y responde: jamás se intenta OpenAI.
    monkeypatch.setattr(modelos_llm, "proveedor_preferido", lambda: "anthropic")
    vistos: list[str] = []

    async def fake_vision(model, system, pedido, imagen, *, max_tokens):
        vistos.append(model)
        return "veo a Claude narrando la escena"

    monkeypatch.setattr(llm, "_vision_en", fake_vision)
    out = await llm.narrar_frame("data:image/jpeg;base64,xxx")
    assert out == "veo a Claude narrando la escena"
    assert all(modelos_llm.proveedor_de_id(m) == "anthropic" for m in vistos)


# ── TTS: cadena ElevenLabs → OpenAI ──────────────────────────────────────────


async def test_tts_sin_eleven_usa_openai(monkeypatch):
    monkeypatch.setattr(llm.settings, "elevenlabs_api_key", "")

    async def fake_openai(texto, voz, model, formato):
        return b"AUDIO_OPENAI"

    monkeypatch.setattr(llm, "_openai_tts", fake_openai)
    audio, prov = await llm.hablar("hola")
    assert audio == b"AUDIO_OPENAI"
    assert prov == "openai"


async def test_tts_eleven_con_key_pero_flag_off_usa_openai(monkeypatch):
    # NUEVO default (voz unificada): aunque haya key de ElevenLabs, si el flag
    # tts_elevenlabs_activo está OFF, ElevenLabs queda FUERA de la cadena y el
    # cloud es OpenAI (último recurso). La voz por defecto es la del dispositivo.
    monkeypatch.setattr(llm.settings, "elevenlabs_api_key", "k")
    monkeypatch.setattr(llm.settings, "tts_elevenlabs_activo", False)

    async def fake_eleven(texto, formato):
        raise AssertionError("ElevenLabs no debe llamarse con el flag OFF")

    async def fake_openai(texto, voz, model, formato):
        return b"AUDIO_OPENAI"

    monkeypatch.setattr(llm, "_eleven_tts", fake_eleven)
    monkeypatch.setattr(llm, "_openai_tts", fake_openai)
    audio, prov = await llm.hablar("hola")
    assert prov == "openai"


async def test_tts_con_eleven_activo_usa_eleven(monkeypatch):
    # Solo si se ACTIVA explícito (flag + key) ElevenLabs vuelve a la cadena.
    monkeypatch.setattr(llm.settings, "elevenlabs_api_key", "k")
    monkeypatch.setattr(llm.settings, "tts_elevenlabs_activo", True)

    async def fake_eleven(texto, formato):
        return b"AUDIO_ELEVEN"

    monkeypatch.setattr(llm, "_eleven_tts", fake_eleven)
    audio, prov = await llm.hablar("hola")
    assert prov == "elevenlabs"


async def test_tts_eleven_cae_a_openai(monkeypatch):
    monkeypatch.setattr(llm.settings, "elevenlabs_api_key", "k")
    monkeypatch.setattr(llm.settings, "tts_elevenlabs_activo", True)

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
