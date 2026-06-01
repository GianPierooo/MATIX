"""Idempotencia + reconciliación de los turnos del chat.

Si el usuario sale de la app a mitad de un turno, la conexión se aborta pero
el cerebro YA está procesando. Para que al volver/reintentar NO se pierda el
resultado ni se dupliquen escrituras, cada turno trae una `idempotency_key`
(la app la reusa si reintenta) y acá:

- La PRIMERA vez con esa clave: marcamos `procesando`, corremos el turno, y al
  terminar guardamos el resultado como `ok`. Lo devolvemos.
- Un REINTENTO con la misma clave:
  - si ya está `ok` → devolvemos el resultado guardado SIN re-ejecutar (no se
    duplican gastos/tareas; y la app recupera la respuesta que perdió en vuelo).
  - si sigue `procesando` → `EnProceso` (el router responde 409; reintentar en
    un momento).
  - si quedó en `error` → se vuelve a ejecutar (no llegó a persistir el ok).

`db` es el wrapper Postgrest. `ejecutar` es una corutina sin argumentos que
hace el trabajo real (correr `conversar`) y devuelve el dict del ChatResponse.
"""
from __future__ import annotations

from collections.abc import Awaitable, Callable
from typing import Any

_TABLA = "chat_operaciones"


class EnProceso(Exception):
    """La operación con esa clave sigue corriendo (otro request en vuelo)."""


async def _fila(db, key: str) -> dict[str, Any] | None:
    filas = await db.list(_TABLA, filters={"idempotency_key": key}, limit=1)
    return filas[0] if filas else None


async def ejecutar_idempotente(
    db,
    key: str,
    ejecutar: Callable[[], Awaitable[dict[str, Any]]],
) -> dict[str, Any]:
    """Corre `ejecutar()` una sola vez por `key`; reintentos devuelven el
    resultado guardado. Lanza `EnProceso` si hay otra corrida en vuelo."""
    existente = await _fila(db, key)
    if existente is not None:
        estado = existente.get("estado")
        if estado == "ok":
            # Reconciliación + idempotencia: el resultado ya está; lo devolvemos
            # sin re-ejecutar nada (cero escrituras duplicadas).
            return existente.get("resultado") or {}
        if estado == "procesando":
            raise EnProceso()
        # estado == "error": no llegó a persistir el ok → reintentamos.
        op_id = existente["id"]
        await db.update(_TABLA, op_id, {"estado": "procesando", "resultado": None})
    else:
        # Marcar procesando ANTES de ejecutar. Si dos requests con la misma
        # clave corren a la vez, el `unique` hace que el segundo `insert` falle
        # → lo tratamos como "en proceso".
        try:
            fila = await db.insert(
                _TABLA, {"idempotency_key": key, "estado": "procesando"}
            )
            op_id = fila["id"]
        except Exception as e:  # noqa: BLE001
            raise EnProceso() from e

    try:
        resultado = await ejecutar()
    except Exception:
        try:
            await db.update(_TABLA, op_id, {"estado": "error"})
        except Exception:  # noqa: BLE001
            pass
        raise

    await db.update(
        _TABLA, op_id, {"estado": "ok", "resultado": resultado}
    )
    return resultado
