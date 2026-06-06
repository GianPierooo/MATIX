"""Canal de comunicación con el agente local de la PC.

Mantiene la conexión WebSocket viva (una sola, app de un solo usuario) y permite
que una tool del modelo envíe una acción y espere el resultado, correlando por
id. Si el agente no está conectado, responde limpio y al instante — nunca se
cuelga esperando.

Anti-inyección: este módulo trata todo lo que llega del agente como DATO. El
resultado se le devuelve a la tool y de ahí al modelo como contenido de un
mensaje `tool` (nunca como instrucciones). El canal no interpreta nada.
"""
from __future__ import annotations

import asyncio
import logging
from typing import Any, Protocol

logger = logging.getLogger("matix.agente")

# Timeout por acción. Un listado de nombres vuelve en milisegundos; si el agente
# no respondió en este margen, asumimos que algo se atascó.
TIMEOUT_ACCION = 20.0


class WSLike(Protocol):
    """Lo mínimo que el canal usa de un WebSocket (Starlette o un fake en tests)."""

    async def send_json(self, data: Any) -> None: ...
    async def close(self, code: int = 1000, reason: str = "") -> None: ...


class CanalAgente:
    def __init__(self) -> None:
        self._ws: WSLike | None = None
        self._pendientes: dict[str, asyncio.Future] = {}
        self._contador = 0

    @property
    def conectado(self) -> bool:
        return self._ws is not None

    async def registrar(self, ws: WSLike) -> None:
        """Registra una conexión nueva. Newest-wins: si había una vieja (p. ej.
        un socket muerto que no se enteró de su caída), la cerramos."""
        viejo = self._ws
        self._ws = ws
        if viejo is not None and viejo is not ws:
            try:
                await viejo.close(code=1012, reason="reemplazada por nueva conexión")
            except Exception:  # noqa: BLE001 — cerrar el viejo es best-effort
                pass

    async def desregistrar(self, ws: WSLike) -> None:
        """Quita la conexión (si es la actual) y falla las llamadas pendientes."""
        if self._ws is ws:
            self._ws = None
        for fut in list(self._pendientes.values()):
            if not fut.done():
                fut.set_result(
                    {"ok": False, "tipo": "pc_desconectada",
                     "mensaje": "La PC se desconectó antes de responder."}
                )
        self._pendientes.clear()

    def resolver(self, msg: dict) -> None:
        """El router llama esto cuando llega un mensaje `resultado` del agente."""
        rid = msg.get("id")
        if rid is None:
            return
        fut = self._pendientes.get(str(rid))
        if fut is not None and not fut.done():
            fut.set_result(msg.get("resultado") or {})

    async def enviar_accion(
        self, nombre: str, args: dict[str, Any], *, timeout: float = TIMEOUT_ACCION
    ) -> dict[str, Any]:
        """Envía una acción al agente y espera su resultado.

        Devuelve siempre un dict; nunca lanza por desconexión/timeout.
        """
        ws = self._ws
        if ws is None:
            return {
                "ok": False,
                "tipo": "pc_desconectada",
                "mensaje": "Tu PC no está conectada a Matix ahora mismo.",
            }

        self._contador += 1
        rid = f"a{self._contador}"
        loop = asyncio.get_running_loop()
        fut: asyncio.Future = loop.create_future()
        self._pendientes[rid] = fut
        try:
            await ws.send_json(
                {"tipo": "accion", "id": rid, "nombre": nombre, "args": args}
            )
            return await asyncio.wait_for(fut, timeout=timeout)
        except asyncio.TimeoutError:
            return {
                "ok": False,
                "tipo": "timeout",
                "mensaje": "Tu PC no respondió a tiempo.",
            }
        except Exception as e:  # noqa: BLE001 — el canal nunca tumba el chat
            logger.warning("canal agente: fallo enviando acción %s: %s", nombre, type(e).__name__)
            return {
                "ok": False,
                "tipo": "error_canal",
                "mensaje": "No pude hablar con tu PC.",
            }
        finally:
            self._pendientes.pop(rid, None)


# Singleton del proceso (el cerebro mantiene una sola conexión de PC).
canal = CanalAgente()
