"""Flujo del horario (H1) con un FakeDB en memoria: marcar hecho, saltar y
empujar al calendario (idempotente). Sin BD real — verifica el cableado de las
acciones del loop sin tocar prod."""
from __future__ import annotations

import asyncio

from app.matix import horario


class FakeDB:
    """Postgrest mínimo en memoria: list/insert/update por tabla."""

    def __init__(self, tablas: dict[str, list[dict]] | None = None):
        self.tablas: dict[str, list[dict]] = tablas or {}
        self.updates: list[tuple[str, str, dict]] = []
        self.inserts: list[tuple[str, dict]] = []

    async def list(self, tabla, *, filters=None, raw_filters=None, order=None, limit=None):
        filas = list(self.tablas.get(tabla, []))
        if filters:
            for k, v in filters.items():
                filas = [f for f in filas if f.get(k) == v]
        return filas

    async def insert(self, tabla, row):
        fila = {"id": f"{tabla}-{len(self.inserts)}", **row}
        self.tablas.setdefault(tabla, []).append(fila)
        self.inserts.append((tabla, row))
        return fila

    async def update(self, tabla, id_, payload):
        self.updates.append((tabla, id_, payload))
        for f in self.tablas.get(tabla, []):
            if f.get("id") == id_:
                f.update(payload)
                return f
        return {"id": id_, **payload}


def test_empujar_a_calendario_es_idempotente():
    db = FakeDB()
    bloques = [
        {"titulo": "OneXotic: sprint", "inicio": "08:00", "fin": "09:30"},
        {"titulo": "Práctica: Inglés", "inicio": "10:00", "fin": "10:30"},
    ]
    # Primera vez: crea los 2.
    r1 = asyncio.run(horario.empujar_a_calendario(db, bloques=bloques))
    assert r1["creados"] == 2 and r1["omitidos"] == 0
    assert len(db.tablas.get("eventos", [])) == 2
    # Segunda vez (mismos bloques): no duplica.
    r2 = asyncio.run(horario.empujar_a_calendario(db, bloques=bloques))
    assert r2["creados"] == 0 and r2["omitidos"] == 2
    assert len(db.tablas.get("eventos", [])) == 2  # sigue habiendo 2, no 4


def test_completar_bloque_cierra_nodo_y_tarea():
    db = FakeDB()
    r = asyncio.run(horario.completar_bloque(db, tarea_id="t1", nodo_id="n1"))
    assert r["ok"] is True
    tablas = {t for t, _, _ in db.updates}
    assert "arbol_nodos" in tablas  # marcó el nodo hecho
    assert "tareas" in tablas       # completó la tarea
    # El nodo quedó 'hecho' y la tarea 'completada'.
    assert any(t == "arbol_nodos" and p.get("estado") == "hecho" for t, _, p in db.updates)
    assert any(t == "tareas" and p.get("completada") is True for t, _, p in db.updates)


def test_completar_bloque_solo_nodo():
    db = FakeDB()
    asyncio.run(horario.completar_bloque(db, nodo_id="n9"))
    tablas = {t for t, _, _ in db.updates}
    assert tablas == {"arbol_nodos"}  # sin tarea, solo el nodo


def test_saltar_bloque_marca_set_item():
    db = FakeDB()
    asyncio.run(horario.saltar_bloque(db, set_item_id="s1"))
    assert ("set_diario_items", "s1", {"estado": "saltado"}) in db.updates
