"""Integridad de datos en Finanzas.

- `inferir_tipo`: clasifica gasto/ingreso por señal (signo/keyword).
- `registrar_movimientos`: preview (no escribe) vs confirmado (escribe con
  lote_id); respeta el filtro «solo gastos»; corrige el tipo por la señal.
- `revertir_ultimo_lote`: borra SOLO el último lote, nunca lo demás.

FakeDB simula insert / list (con order/filters/raw_filters/limit) / delete_where.
"""
from __future__ import annotations

from typing import Any

from app.matix import finanzas, tools


# ── inferir_tipo ────────────────────────────────────────────────────
def test_inferir_tipo_por_signo():
    assert finanzas.inferir_tipo("-30") == "gasto"
    assert finanzas.inferir_tipo("S/ -30.00") == "gasto"
    assert finanzas.inferir_tipo("+50") == "ingreso"
    assert finanzas.inferir_tipo("(20)") == "gasto"


def test_inferir_tipo_por_palabra():
    assert finanzas.inferir_tipo("Pagaste a Juan") == "gasto"
    assert finanzas.inferir_tipo("Te yapearon") == "ingreso"
    assert finanzas.inferir_tipo("Abono de sueldo") == "ingreso"
    assert finanzas.inferir_tipo("monto en rojo") == "gasto"


def test_inferir_tipo_ambiguo_es_none():
    assert finanzas.inferir_tipo("30 soles") is None
    assert finanzas.inferir_tipo("") is None
    assert finanzas.inferir_tipo(None) is None


# ── FakeDB ──────────────────────────────────────────────────────────
class FakeDB:
    def __init__(self):
        self.rows: list[dict[str, Any]] = []
        self._n = 0

    async def insert(self, table, payload):
        self._n += 1
        fila = {"id": f"id-{self._n}", "creado_en": self._n, **payload}
        self.rows.append(fila)
        return dict(fila)

    async def list(self, table, *, order=None, limit=None, filters=None, raw_filters=None, select=None):
        out = list(self.rows)
        if raw_filters and raw_filters.get("lote_id") == "not.is.null":
            out = [r for r in out if r.get("lote_id") is not None]
        if filters:
            for k, v in filters.items():
                out = [r for r in out if str(r.get(k)) == str(v)]
        if order == "creado_en.desc":
            out.sort(key=lambda r: r.get("creado_en", 0), reverse=True)
        if limit is not None:
            out = out[:limit]
        return out

    async def delete_where(self, table, *, filters):
        antes = len(self.rows)
        self.rows = [
            r for r in self.rows
            if not all(str(r.get(k)) == str(v) for k, v in filters.items())
        ]
        return antes - len(self.rows)

    async def get(self, table, row_id):
        return next((dict(r) for r in self.rows if r["id"] == row_id), None)

    async def delete(self, table, row_id):
        antes = len(self.rows)
        self.rows = [r for r in self.rows if r["id"] != row_id]
        return len(self.rows) < antes


# ── registrar_movimientos ───────────────────────────────────────────
async def test_preview_no_escribe():
    db = FakeDB()
    r = await tools._registrar_movimientos(
        db,
        {"movimientos": [
            {"tipo": "gasto", "monto": 30, "categoria": "Comida"},
            {"tipo": "ingreso", "monto": 50},
        ]},
    )
    assert r["ok"] and r["datos"]["preview"] is True
    assert r["datos"]["n"] == 2
    assert db.rows == []  # NADA escrito en preview


async def test_confirmado_escribe_con_lote_compartido():
    db = FakeDB()
    r = await tools._registrar_movimientos(
        db,
        {"confirmado": True, "movimientos": [
            {"tipo": "gasto", "monto": 30},
            {"tipo": "gasto", "monto": 12},
        ]},
    )
    assert r["ok"] and r["datos"]["registrado"] is True
    assert len(db.rows) == 2
    lotes = {row["lote_id"] for row in db.rows}
    assert len(lotes) == 1  # mismo lote_id para todo el lote
    assert r["datos"]["lote_id"] == next(iter(lotes))


async def test_filtro_solo_gastos_descarta_ingresos():
    db = FakeDB()
    r = await tools._registrar_movimientos(
        db,
        {"confirmado": True, "filtro": "solo_gastos", "movimientos": [
            {"tipo": "gasto", "monto": 30},
            {"tipo": "ingreso", "monto": 500},   # debe descartarse
            {"tipo": "gasto", "monto": 8},
        ]},
    )
    assert r["ok"]
    assert all(row["tipo"] == "gasto" for row in db.rows)
    assert len(db.rows) == 2
    assert r["datos"]["descartados_por_filtro"] == 1


async def test_senal_corrige_tipo_mal_clasificado():
    db = FakeDB()
    # El modelo propuso "gasto" pero la señal dice +50 (ingreso): se corrige.
    r = await tools._registrar_movimientos(
        db,
        {"confirmado": True, "movimientos": [
            {"tipo": "gasto", "monto": 50, "senal": "+50 Te yapearon"},
        ]},
    )
    assert r["ok"]
    assert db.rows[0]["tipo"] == "ingreso"

    # Y con filtro solo_gastos, ese ingreso (corregido) se descarta.
    db2 = FakeDB()
    r2 = await tools._registrar_movimientos(
        db2,
        {"confirmado": True, "filtro": "solo_gastos", "movimientos": [
            {"tipo": "gasto", "monto": 50, "senal": "+50"},
        ]},
    )
    assert not r2["ok"]  # no queda nada para registrar


# ── revertir_ultimo_lote ────────────────────────────────────────────
async def test_revertir_solo_toca_el_ultimo_lote():
    db = FakeDB()
    # Movimiento creado a mano (sin lote): NO debe tocarse nunca.
    await db.insert("movimientos", {"tipo": "gasto", "monto": 99, "lote_id": None})
    # Lote 1 (más viejo).
    await tools._registrar_movimientos(
        db, {"confirmado": True, "movimientos": [{"tipo": "gasto", "monto": 10}]}
    )
    # Lote 2 (más nuevo): dos gastos.
    await tools._registrar_movimientos(
        db,
        {"confirmado": True, "movimientos": [
            {"tipo": "gasto", "monto": 20}, {"tipo": "gasto", "monto": 30},
        ]},
    )
    assert len(db.rows) == 4

    # Preview: muestra 2 (el último lote), no borra.
    prev = await tools._revertir_ultimo_lote(db, {})
    assert prev["ok"] and prev["datos"]["preview"] is True
    assert prev["datos"]["n"] == 2
    assert len(db.rows) == 4

    # Confirmado: borra SOLO el último lote (2). Quedan el manual y el lote 1.
    rev = await tools._revertir_ultimo_lote(db, {"confirmado": True})
    assert rev["ok"] and rev["datos"]["borrados"] == 2
    montos = sorted(row["monto"] for row in db.rows)
    assert montos == [10, 99]  # el lote viejo y el manual, intactos


async def test_revertir_sin_lotes_avisa():
    db = FakeDB()
    await db.insert("movimientos", {"tipo": "gasto", "monto": 5, "lote_id": None})
    r = await tools._revertir_ultimo_lote(db, {"confirmado": True})
    assert not r["ok"]  # no hay lote que revertir; no toca el manual
    assert len(db.rows) == 1
