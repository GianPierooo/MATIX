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


def test_agendar_sugerencia_crea_tarea_no_evento():
    """El bug recurrente: agregar una sugerencia debe crear una TAREA, nunca un
    Evento de calendario. Una sugerencia sin tarea_id (skill / sintetizada) →
    nace como Tarea (aparece en Tareas) con su bloque (aparece en Tu día)."""
    db = FakeDB()
    bloques = [
        {"titulo": "Práctica: Inglés", "inicio": "10:00", "fin": "10:30",
         "proyecto_id": "skill-ing"},
    ]
    r = asyncio.run(horario.agendar_plan(db, bloques=bloques))
    assert r["agendadas"] == 1
    # Creó una TAREA (con bloque) y NINGÚN evento.
    tareas = db.tablas.get("tareas", [])
    assert len(tareas) == 1
    assert tareas[0]["titulo"] == "Práctica: Inglés"
    assert tareas[0].get("bloque_inicio") and tareas[0].get("vence_en")
    assert db.tablas.get("eventos", []) == []  # NUNCA un evento pelado
    # Dedup: re-agendar lo mismo no duplica.
    r2 = asyncio.run(horario.agendar_plan(db, bloques=bloques))
    assert r2["omitidas"] == 1
    assert len(db.tablas.get("tareas", [])) == 1


def test_agendar_engancha_tarea_existente_sin_crear_evento():
    """Si el bloque ya viene de una tarea (tarea_id), se ENGANCHA su horario
    (no se crea otra tarea ni un evento)."""
    db = FakeDB()
    bloques = [
        {"titulo": "OneXotic: sprint", "inicio": "08:00", "fin": "09:30",
         "tarea_id": "t1"},
    ]
    r = asyncio.run(horario.agendar_plan(db, bloques=bloques))
    assert r["agendadas"] == 1
    # Actualizó la tarea t1 con su bloque; sin tareas nuevas ni eventos.
    assert any(t == "tareas" and id_ == "t1" and "bloque_inicio" in p
               for t, id_, p in db.updates)
    assert db.tablas.get("tareas", []) == []  # no insertó tarea nueva
    assert db.tablas.get("eventos", []) == []  # ni evento


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
