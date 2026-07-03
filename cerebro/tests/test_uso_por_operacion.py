"""Telemetría de tokens por-operación (T2): desglose `por_operacion` + log
estructurado, sin contenido sensible. Tests puros (sin red)."""
from __future__ import annotations

import logging

from app.matix.uso import MedidorUso, operacion, operacion_ctx


def _usage(inp: int, out: int, cached: int = 0) -> dict:
    return {
        "prompt_tokens": inp,
        "completion_tokens": out,
        "prompt_tokens_details": {"cached_tokens": cached},
    }


def test_registrar_chat_operacion_explicita_va_a_por_operacion():
    m = MedidorUso()
    m.registrar_chat(_usage(100, 40), proveedor="openai", operacion="chat", modelo="gpt-4o-mini")
    snap = m.snapshot()
    assert "por_operacion" in snap
    chat = snap["por_operacion"]["chat"]
    assert chat["llamadas"] == 1
    assert chat["tokens_in"] == 100
    assert chat["tokens_out"] == 40
    assert chat["costo_usd"] > 0


def test_operacion_context_var_etiqueta_sin_pasar_param():
    m = MedidorUso()
    with operacion("extraccion:recibo"):
        m.registrar_chat(_usage(50, 5), proveedor="openai")  # operacion=None → lee ctx
    snap = m.snapshot()
    assert "extraccion:recibo" in snap["por_operacion"]
    assert snap["por_operacion"]["extraccion:recibo"]["llamadas"] == 1
    # El ContextVar se restaura al salir del `with`.
    assert operacion_ctx.get() == "chat"


def test_default_es_chat():
    m = MedidorUso()
    m.registrar_chat(_usage(10, 2), proveedor="openai")  # sin operacion ni ctx → chat
    assert "chat" in m.snapshot()["por_operacion"]


def test_embedding_whisper_tts_etiquetan_su_operacion():
    m = MedidorUso()
    m.registrar_embedding(1000)
    m.registrar_whisper(30.0)
    m.registrar_tts(500)
    po = m.snapshot()["por_operacion"]
    assert po["embedding"]["tokens_in"] == 1000 and po["embedding"]["costo_usd"] > 0
    assert po["whisper"]["llamadas"] == 1 and po["whisper"]["costo_usd"] > 0
    assert po["tts"]["llamadas"] == 1 and po["tts"]["costo_usd"] > 0


def test_acumula_varias_llamadas_de_la_misma_operacion():
    m = MedidorUso()
    with operacion("chat"):
        m.registrar_chat(_usage(100, 10), proveedor="openai")
        m.registrar_chat(_usage(200, 20), proveedor="anthropic")
    chat = m.snapshot()["por_operacion"]["chat"]
    assert chat["llamadas"] == 2
    assert chat["tokens_in"] == 300
    assert chat["tokens_out"] == 30


def test_emite_log_estructurado_sin_contenido(caplog):
    m = MedidorUso()
    with caplog.at_level(logging.INFO, logger="matix.uso"):
        m.registrar_chat(
            _usage(100, 40), proveedor="openai", operacion="chat", modelo="gpt-4o-mini"
        )
    linea = "\n".join(caplog.messages)
    assert "llm_uso" in linea
    assert "op=chat" in linea
    assert "in=100" in linea and "out=40" in linea
