"""Reintentos con backoff ante errores TRANSITORIOS de proveedor (`_con_reintentos`).

Cubre lo que blinda el TTS y la narración de cámara: un 502/timeout pasajero de
OpenAI se reintenta en vez de tumbar la voz; un error legítimo (400/validación)
NO se reintenta. Sin red ni BD (base_delay=0 para no dormir)."""
from __future__ import annotations

import pytest

from app.matix import llm


class _Err502(Exception):
    """Simula un 5xx de proveedor (transitorio)."""
    status_code = 502


async def test_reintenta_y_logra_tras_transitorios():
    n = {"i": 0}

    async def hacer():
        n["i"] += 1
        if n["i"] < 3:
            raise _Err502()
        return "ok"

    r = await llm._con_reintentos(hacer, intentos=3, base_delay=0)
    assert r == "ok"
    assert n["i"] == 3  # falló 2 veces, logró a la 3ª


async def test_agota_intentos_y_relanza():
    async def hacer():
        raise _Err502()

    with pytest.raises(_Err502):
        await llm._con_reintentos(hacer, intentos=3, base_delay=0)


async def test_no_reintenta_error_legitimo():
    n = {"i": 0}

    async def hacer():
        n["i"] += 1
        raise ValueError("bad request")  # no es error de proveedor

    with pytest.raises(ValueError):
        await llm._con_reintentos(hacer, intentos=3, base_delay=0)
    assert n["i"] == 1  # sin reintentos: se relanza de inmediato
