"""Reconexión del cliente WS (Capa 6).

El backoff debe RESETEARSE tras una conexión SANA: una caída después de haber
conectado (p. ej. el proxy de Railway corta WS de larga duración) se reintenta
rápido (~1s), no arrastra los ~60s del backoff previo — si no, la PC queda
"desconectada" ~1 min por cada corte y "Recomprobar PC" la ve caída.

Sin red: se inyectan `_sesion` y `_esperar_o_stop` falsos.
"""
from __future__ import annotations

import asyncio

from websockets.exceptions import WebSocketException

from agente_pc import cliente
from agente_pc.cliente import BACKOFF_MIN


def test_backoff_se_resetea_tras_conexion_sana(monkeypatch) -> None:
    esperas: list[float] = []

    async def fake_sesion(config, registro, ctx, stop, log, conecto=None):
        # Conecta OK y luego se cae (como un corte de proxy).
        if conecto is not None:
            conecto[0] = True
        raise WebSocketException("drop")

    async def fake_esperar(seg, stop):
        esperas.append(seg)
        if len(esperas) >= 5:
            stop.set()  # corta el loop

    monkeypatch.setattr(cliente, "_sesion", fake_sesion)
    monkeypatch.setattr(cliente, "_esperar_o_stop", fake_esperar)

    asyncio.run(cliente.correr(None, None, None, asyncio.Event(), log=lambda m: None))

    # Cada sesión CONECTÓ → backoff siempre en MIN → todas las esperas ~1s
    # (jitter 0.8–1.2), NUNCA escalan a 60.
    assert esperas, "debió reintentar"
    assert all(e <= BACKOFF_MIN * 1.3 for e in esperas), esperas


def test_backoff_escala_si_nunca_conecta(monkeypatch) -> None:
    esperas: list[float] = []

    async def fake_sesion(config, registro, ctx, stop, log, conecto=None):
        # Nunca conecta (cerebro caído): `conecto` queda en False.
        raise OSError("sin ruta")

    async def fake_esperar(seg, stop):
        esperas.append(seg)
        if len(esperas) >= 4:
            stop.set()

    monkeypatch.setattr(cliente, "_sesion", fake_sesion)
    monkeypatch.setattr(cliente, "_esperar_o_stop", fake_esperar)

    asyncio.run(cliente.correr(None, None, None, asyncio.Event(), log=lambda m: None))

    # Backoff exponencial real cuando NO conecta: la última espera es mucho
    # mayor que la primera (los rangos no se solapan ni con jitter).
    assert len(esperas) >= 4
    assert esperas[-1] > esperas[0]
