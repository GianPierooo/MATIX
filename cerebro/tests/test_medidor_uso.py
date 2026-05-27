"""Tests del medidor de uso (sin pegarle a OpenAI)."""
from __future__ import annotations

from httpx import AsyncClient

from app.matix.uso import MedidorUso, medidor


def test_medidor_registra_y_calcula_costo() -> None:
    m = MedidorUso()
    # Simulamos un usage como el de OpenAI (objeto-like vía dict).
    usage = {
        "prompt_tokens": 1000,
        "completion_tokens": 500,
        "prompt_tokens_details": {"cached_tokens": 200},
    }
    m.registrar_chat(usage)
    snap = m.snapshot()
    assert snap["prompt_tokens"] == 1000
    assert snap["cached_prompt_tokens"] == 200
    assert snap["completion_tokens"] == 500
    assert snap["total_tokens"] == 1500
    assert snap["llamadas_chat"] == 1
    # Costo: 800 input * 0.150/1M + 200 cached * 0.075/1M + 500 out * 0.600/1M
    esperado = (
        800 * 0.150 / 1_000_000
        + 200 * 0.075 / 1_000_000
        + 500 * 0.600 / 1_000_000
    )
    assert abs(snap["costo_usd"] - round(esperado, 6)) < 1e-9


def test_medidor_acumula_sobre_varias_llamadas() -> None:
    m = MedidorUso()
    m.registrar_chat({"prompt_tokens": 100, "completion_tokens": 50})
    m.registrar_chat({"prompt_tokens": 200, "completion_tokens": 100})
    snap = m.snapshot()
    assert snap["prompt_tokens"] == 300
    assert snap["completion_tokens"] == 150
    assert snap["llamadas_chat"] == 2


def test_medidor_registra_whisper() -> None:
    m = MedidorUso()
    m.registrar_whisper(60.0)  # 1 minuto
    snap = m.snapshot()
    assert snap["segundos_whisper"] == 60.0
    assert snap["llamadas_whisper"] == 1
    # 1 minuto = $0.006
    assert abs(snap["costo_usd"] - 0.006) < 1e-9


def test_medidor_tolera_usage_none() -> None:
    m = MedidorUso()
    m.registrar_chat(None)  # no debe explotar
    snap = m.snapshot()
    assert snap["llamadas_chat"] == 0


async def test_endpoint_uso(client: AsyncClient) -> None:
    # Reiniciamos el singleton para no depender de tests previos.
    medidor.reiniciar()
    r = await client.get("/api/v1/matix/uso")
    assert r.status_code == 200
    j = r.json()
    assert j["total_tokens"] == 0
    assert j["costo_usd"] == 0
    assert "precios" in j
