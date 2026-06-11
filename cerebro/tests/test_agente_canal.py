"""Canal cerebro ↔ agente local (Capa 6 · 6.0a).

Tests PUROS (sin BD, sin red real): un WebSocket falso ejercita el canal.
Cubren el caso clave del spec: si la PC no está conectada, se responde limpio y
al instante — nunca se cuelga esperando.
"""
from __future__ import annotations

import asyncio

from app.agente.canal import CanalAgente, canal


class FakeWS:
    """WebSocket mínimo para tests: registra lo enviado, marca si se cerró."""

    def __init__(self) -> None:
        self.enviados: list[dict] = []
        self.cerrado = False

    async def send_json(self, data: dict) -> None:
        self.enviados.append(data)

    async def close(self, code: int = 1000, reason: str = "") -> None:
        self.cerrado = True


async def test_desconectado_responde_limpio():
    c = CanalAgente()
    res = await c.enviar_accion("listar_carpeta", {"ruta": "x"})
    assert res["ok"] is False
    assert res["tipo"] == "pc_desconectada"


async def test_round_trip_resuelve_por_id():
    c = CanalAgente()
    ws = FakeWS()
    await c.registrar(ws)

    async def responder():
        while not ws.enviados:
            await asyncio.sleep(0)
        rid = ws.enviados[-1]["id"]
        c.resolver({"tipo": "resultado", "id": rid,
                    "resultado": {"ok": True, "entradas": []}})

    res, _ = await asyncio.gather(
        c.enviar_accion("listar_carpeta", {"ruta": "x"}, timeout=2),
        responder(),
    )
    assert res["ok"] is True
    assert ws.enviados[-1]["tipo"] == "accion"
    assert ws.enviados[-1]["nombre"] == "listar_carpeta"


async def test_timeout_si_no_responde():
    c = CanalAgente()
    await c.registrar(FakeWS())
    res = await c.enviar_accion("listar_carpeta", {"ruta": "x"}, timeout=0.05)
    assert res["ok"] is False
    assert res["tipo"] == "timeout"


async def test_newest_wins_cierra_la_vieja():
    c = CanalAgente()
    vieja = FakeWS()
    nueva = FakeWS()
    await c.registrar(vieja)
    await c.registrar(nueva)
    assert vieja.cerrado is True
    assert c.conectado is True


async def test_desregistrar_libera_pendientes():
    c = CanalAgente()
    ws = FakeWS()
    await c.registrar(ws)

    async def desconectar():
        while not ws.enviados:
            await asyncio.sleep(0)
        await c.desregistrar(ws)

    res, _ = await asyncio.gather(
        c.enviar_accion("listar_carpeta", {"ruta": "x"}, timeout=2),
        desconectar(),
    )
    assert res["ok"] is False
    assert res["tipo"] == "pc_desconectada"
    assert c.conectado is False


async def test_tool_pc_listar_carpeta_desconectada():
    """La tool del modelo responde limpio cuando no hay agente conectado."""
    from app.matix import tools

    assert canal.conectado is False
    res = await tools.ejecutar_tool(None, "pc_listar_carpeta", {"ruta": "Documentos"})
    assert res["ok"] is False
    assert res["tipo"] == "pc_desconectada"


async def test_gracia_espera_reconexion_reciente():
    """Si el WS cayó hace poco (blip) y reconecta, `_ws_vivo` espera y agarra la
    nueva conexión en vez de fallar al instante."""
    c = CanalAgente()
    ws1 = FakeWS()
    await c.registrar(ws1)
    await c.desregistrar(ws1)  # cayó recién
    ws2 = FakeWS()

    async def reconecta():
        await asyncio.sleep(0.05)
        await c.registrar(ws2)

    t = asyncio.create_task(reconecta())
    vivo = await c._ws_vivo(gracia=2.0)
    await t
    assert vivo is ws2  # esperó el blip y tomó la reconexión


async def test_sin_conexion_previa_responde_al_instante():
    """Si nunca hubo agente, NO esperamos la gracia: desconectada al instante."""
    import time as _t
    c = CanalAgente()
    t0 = _t.monotonic()
    vivo = await c._ws_vivo(gracia=5.0)
    assert vivo is None
    assert _t.monotonic() - t0 < 0.5  # no colgó esperando
