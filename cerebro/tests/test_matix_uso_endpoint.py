"""Endpoint `/api/v1/matix/uso` end-to-end (sin pegarle a OpenAI).

Inyecta valores en el medidor singleton y verifica que el endpoint
los devuelve con la estructura esperada — incluye el contrato que
consume la franja del medidor en la app Flutter.
"""
from __future__ import annotations

from httpx import AsyncClient

from app.matix.uso import medidor


async def test_endpoint_uso_estructura_completa(client: AsyncClient) -> None:
    medidor.reiniciar()
    medidor.registrar_chat(
        {
            "prompt_tokens": 800,
            "completion_tokens": 200,
            "prompt_tokens_details": {"cached_tokens": 300},
        }
    )
    medidor.registrar_whisper(30.0)  # 0.5 min
    medidor.registrar_tts(150)  # 150 chars

    r = await client.get("/api/v1/matix/uso")
    assert r.status_code == 200
    j = r.json()
    # Campos que la franja del medidor consume directo.
    assert j["prompt_tokens"] == 800
    assert j["cached_prompt_tokens"] == 300
    assert j["completion_tokens"] == 200
    assert j["total_tokens"] == 1000
    assert j["llamadas_chat"] == 1
    assert j["segundos_whisper"] == 30.0
    assert j["llamadas_whisper"] == 1
    assert j["caracteres_tts"] == 150
    assert j["llamadas_tts"] == 1
    assert j["costo_usd"] > 0
    # `precios` se expone para que la UI pueda mostrar el desglose si
    # quiere — comprobamos las claves existentes.
    precios = j["precios"]
    assert "input_por_m_usd" in precios
    assert "input_cached_por_m_usd" in precios
    assert "output_por_m_usd" in precios
    assert "whisper_por_min_usd" in precios
    assert "tts_por_m_chars_usd" in precios


async def test_endpoint_uso_sin_auth(client_anon: AsyncClient) -> None:
    r = await client_anon.get("/api/v1/matix/uso")
    assert r.status_code == 401
