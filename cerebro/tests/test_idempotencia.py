"""Idempotencia del chat: misma clave no re-ejecuta (no duplica) y devuelve el
resultado guardado (reconciliación)."""
from __future__ import annotations

import pytest

from app.matix import idempotencia


class FakeDB:
    """Simula chat_operaciones con `unique(idempotency_key)`."""

    def __init__(self):
        self.rows: list[dict] = []
        self._n = 0

    async def list(self, table, *, filters=None, limit=None, **kw):
        out = self.rows
        if filters:
            for k, v in filters.items():
                out = [r for r in out if r.get(k) == v]
        return out[:limit] if limit else out

    async def insert(self, table, payload):
        # unique(idempotency_key): segundo insert con la misma clave revienta.
        if any(r["idempotency_key"] == payload["idempotency_key"] for r in self.rows):
            raise Exception("duplicate key value violates unique constraint")
        self._n += 1
        fila = {"id": f"op-{self._n}", "resultado": None, **payload}
        self.rows.append(fila)
        return dict(fila)

    async def update(self, table, row_id, payload):
        for r in self.rows:
            if r["id"] == row_id:
                r.update(payload)
                return dict(r)
        return None


async def test_misma_clave_ejecuta_una_vez_y_devuelve_lo_guardado():
    db = FakeDB()
    efectos = []  # cada ejecución agrega uno (simula escrituras)

    async def ejecutar():
        efectos.append("escritura")
        return {"respuesta": "hecho", "tablas_cambiadas": ["movimientos"]}

    # 1er turno.
    r1 = await idempotencia.ejecutar_idempotente(db, "k1", ejecutar)
    assert r1["respuesta"] == "hecho"
    assert len(efectos) == 1

    # Reintento con la MISMA clave: no re-ejecuta (no duplica) y devuelve igual.
    r2 = await idempotencia.ejecutar_idempotente(db, "k1", ejecutar)
    assert r2 == r1
    assert len(efectos) == 1  # ← clave: NO se escribió de nuevo

    # La fila quedó ok con el resultado guardado.
    fila = (await db.list("chat_operaciones", filters={"idempotency_key": "k1"}))[0]
    assert fila["estado"] == "ok"
    assert fila["resultado"]["respuesta"] == "hecho"


async def test_claves_distintas_ejecutan_cada_una():
    db = FakeDB()
    n = {"c": 0}

    async def ejecutar():
        n["c"] += 1
        return {"respuesta": str(n["c"])}

    await idempotencia.ejecutar_idempotente(db, "a", ejecutar)
    await idempotencia.ejecutar_idempotente(db, "b", ejecutar)
    assert n["c"] == 2


async def test_procesando_lanza_en_proceso():
    db = FakeDB()
    db.rows.append(
        {"id": "op-x", "idempotency_key": "k", "estado": "procesando", "resultado": None}
    )

    async def ejecutar():
        raise AssertionError("no debió ejecutar")

    with pytest.raises(idempotencia.EnProceso):
        await idempotencia.ejecutar_idempotente(db, "k", ejecutar)


async def test_error_previo_se_reintenta():
    db = FakeDB()
    db.rows.append(
        {"id": "op-e", "idempotency_key": "k", "estado": "error", "resultado": None}
    )
    corrio = {"v": False}

    async def ejecutar():
        corrio["v"] = True
        return {"respuesta": "ok"}

    r = await idempotencia.ejecutar_idempotente(db, "k", ejecutar)
    assert corrio["v"] is True
    assert r["respuesta"] == "ok"
    assert db.rows[0]["estado"] == "ok"


async def test_si_ejecutar_falla_queda_en_error():
    db = FakeDB()

    async def ejecutar():
        raise RuntimeError("boom")

    with pytest.raises(RuntimeError):
        await idempotencia.ejecutar_idempotente(db, "k", ejecutar)
    assert db.rows[0]["estado"] == "error"
