"""Capa de comandos (2.0 · Fase 1) — Tareas piloto.

Verifica el CIMIENTO: el registro de comandos, los handlers canónicos, y que la
UI y la IA enrutan al MISMO comando (una sola ruta). Cubre los bugs que se
consolidan: D1 (la captura crea Tarea, NUNCA Evento) y D5 (completar por
cualquier camino deja el mismo estado). FakeDB en memoria, sin red.
"""
from __future__ import annotations

from app.comandos import registro
from app.matix import chat, horario, tools

_TID = "11111111-1111-1111-1111-111111111111"


class FakeDB:
    """Postgrest mínimo: get/list/insert/update/delete por tabla."""

    def __init__(self, tablas: dict[str, list[dict]] | None = None) -> None:
        self.tablas: dict[str, list[dict]] = tablas or {}
        self.inserts: list[tuple[str, dict]] = []
        self.updates: list[tuple[str, str, dict]] = []
        self._n = 0

    async def get(self, tabla, id_):
        for f in self.tablas.get(tabla, []):
            if f.get("id") == id_:
                return f
        return None

    async def list(self, tabla, *, filters=None, raw_filters=None, order=None, limit=None):
        filas = list(self.tablas.get(tabla, []))
        if filters:
            for k, v in filters.items():
                filas = [f for f in filas if f.get(k) == v]
        return filas

    async def insert(self, tabla, row):
        self._n += 1
        fila = {"id": row.get("id") or f"{tabla}-{self._n}", **row}
        self.tablas.setdefault(tabla, []).append(fila)
        self.inserts.append((tabla, row))
        return fila

    async def update(self, tabla, id_, payload):
        self.updates.append((tabla, id_, payload))
        for f in self.tablas.get(tabla, []):
            if f.get("id") == id_:
                f.update(payload)
                return f
        return None

    async def delete(self, tabla, id_):
        antes = len(self.tablas.get(tabla, []))
        self.tablas[tabla] = [f for f in self.tablas.get(tabla, []) if f.get("id") != id_]
        return len(self.tablas.get(tabla, [])) < antes


def _tareas(db: FakeDB) -> list[dict]:
    return db.tablas.get("tareas", [])


# ── El registro (cimiento) ───────────────────────────────────────────────────


def test_registro_tiene_comandos_de_tareas():
    for n in ("crear_tarea", "editar_tarea", "completar_tarea", "reabrir_tarea",
              "eliminar_tarea", "restaurar_tarea", "crear_tareas"):
        assert registro.existe(n), n
    assert registro.get("crear_tarea").riesgo.value == "consecuente"
    assert "tareas" in registro.get("crear_tarea").tablas


def test_comando_desconocido_no_revienta():
    import asyncio
    r = asyncio.run(registro.ejecutar(FakeDB(), "no_existe_xyz", {}))
    assert r["ok"] is False and r["tipo"] == "desconocido"


# ── Handlers de comando ──────────────────────────────────────────────────────


def test_crear_tarea_inserta():
    import asyncio
    db = FakeDB()
    r = asyncio.run(registro.ejecutar(db, "crear_tarea", {"titulo": "comprar pan"}))
    assert r["ok"] and r["datos"]["titulo"] == "comprar pan"
    assert len(_tareas(db)) == 1


def test_crear_tarea_validacion():
    import asyncio
    r = asyncio.run(registro.ejecutar(FakeDB(), "crear_tarea", {"titulo": ""}))
    assert r["ok"] is False and r["tipo"] == "validacion"


def test_completar_idempotente():
    import asyncio
    db = FakeDB({"tareas": [{"id": _TID, "titulo": "X", "completada": True}]})
    r = asyncio.run(registro.ejecutar(db, "completar_tarea", {"tarea_id": _TID}))
    assert r["ok"] and r["datos"]["ya_estaba_completada"] is True


def test_completar_crea_siguiente_instancia_si_repite():
    import asyncio
    db = FakeDB({"tareas": [{
        "id": _TID, "titulo": "Gym", "completada": False, "prioridad": "media",
        "repeticion": "diaria", "vence_en": "2026-06-10T10:00:00+00:00",
    }]})
    r = asyncio.run(registro.ejecutar(db, "completar_tarea", {"tarea_id": _TID}))
    assert r["ok"] and r["datos"]["repetida"] is True
    # Quedó la original completada + UNA nueva instancia (la repetición).
    assert len(_tareas(db)) == 2
    nuevas = [t for t in _tareas(db) if t["id"] != _TID]
    assert nuevas[0]["titulo"] == "Gym" and not nuevas[0].get("completada")


def test_eliminar_es_suave_y_restaurar():
    import asyncio
    db = FakeDB({"tareas": [{"id": _TID, "titulo": "X"}]})
    r = asyncio.run(registro.ejecutar(db, "eliminar_tarea", {"tarea_id": _TID}))
    assert r["ok"] and _tareas(db)[0].get("eliminado_en")  # soft delete
    r2 = asyncio.run(registro.ejecutar(db, "restaurar_tarea", {"tarea_id": _TID}))
    assert r2["ok"] and _tareas(db)[0].get("eliminado_en") is None


# ── Paridad UI ↔ IA: misma ruta canónica, mismo resultado ────────────────────


def test_ui_y_ia_crean_por_el_mismo_comando():
    """El endpoint (UI) y la tool (IA) llaman al MISMO comando crear_tarea →
    misma fila. Aquí: el comando (lo que llama el router) y la tool producen una
    tarea equivalente."""
    import asyncio
    db_ui = FakeDB()
    db_ia = FakeDB()
    # UI: el router hace exactamente esto.
    r_ui = asyncio.run(registro.ejecutar(db_ui, "crear_tarea", {"titulo": "leer"}, origen="ui"))
    # IA: la tool envuelve el mismo comando.
    r_ia = asyncio.run(tools.ejecutar_tool(db_ia, "crear_tarea", {"titulo": "leer"}))
    assert r_ui["ok"] and r_ia["ok"]
    # Misma entidad creada (titulo); la tool da forma compacta, la UI la fila.
    assert _tareas(db_ui)[0]["titulo"] == _tareas(db_ia)[0]["titulo"] == "leer"
    assert r_ia["datos"]["titulo"] == "leer"  # envelope del LLM


# ── D5: completar por CUALQUIER camino deja el mismo estado ───────────────────


def _tarea_repetible():
    return {
        "id": _TID, "titulo": "Gym", "completada": False, "prioridad": "media",
        "repeticion": "diaria", "vence_en": "2026-06-10T10:00:00+00:00",
    }


def test_d5_completar_por_tool_router_y_bloque_mismo_estado():
    import asyncio

    # 1) Tool de la IA.
    db_tool = FakeDB({"tareas": [_tarea_repetible()]})
    asyncio.run(tools.ejecutar_tool(db_tool, "completar_tarea", {"tarea_id": _TID}))

    # 2) Camino del router (editar con completada=True — lo que hace PATCH).
    db_router = FakeDB({"tareas": [_tarea_repetible()]})
    asyncio.run(registro.ejecutar(
        db_router, "editar_tarea", {"tarea_id": _TID, "completada": True}, origen="ui"))

    # 3) Camino del bloque (Tu día).
    db_bloque = FakeDB({"tareas": [_tarea_repetible()]})
    asyncio.run(horario.completar_bloque(db_bloque, tarea_id=_TID))

    for db in (db_tool, db_router, db_bloque):
        orig = next(t for t in _tareas(db) if t["id"] == _TID)
        assert orig["completada"] is True  # completada por los 3 caminos
        # Y los 3 crearon la SIGUIENTE instancia de la repetición (antes el
        # camino del bloque NO lo hacía — ese era el bug D5).
        assert len(_tareas(db)) == 2, "todos los caminos crean la repetición"


# ── D1: la captura crea Tarea y NUNCA Evento ─────────────────────────────────


def test_d1_whitelist_captura_no_expone_evento():
    assert "crear_evento" not in chat._TOOLS_CAPTURA
    nombres = {t["function"]["name"] for t in chat._tools_para_captura()}
    assert nombres == {"crear_tarea", "crear_apunte"}


def test_d1_captura_crea_tarea_nunca_evento(monkeypatch):
    """La captura clasifica y crea por el comando crear_tarea. Aunque el modelo
    se equivocara, la whitelist + el comando hacen imposible un Evento."""
    import asyncio

    db = FakeDB()

    async def fake_responder(messages, tools_, **kw):
        # El modelo "decide" crear_tarea (la única ruta posible es tarea/apunte).
        return {
            "tipo": "tool_calls",
            "tool_calls": [{"id": "c1", "nombre": "crear_tarea", "args": {"titulo": "comprar pan"}}],
            "raw": {},
        }

    async def fake_ctx(_db):
        return ""

    async def fake_modelo(_db):
        return "gpt-4o-mini"

    monkeypatch.setattr(chat.llm, "responder_con_tools", fake_responder)
    monkeypatch.setattr(chat, "contexto_vivo", fake_ctx)
    monkeypatch.setattr(chat.modelos_llm, "modelo_seleccionado", fake_modelo)
    monkeypatch.setattr(chat, "system_prompt_fijo", lambda: "")

    res = asyncio.run(chat.capturar_apunte(db, texto="comprar pan"))
    assert res["tipo"] == "tarea"
    assert res["ok"] is True
    assert len(db.tablas.get("tareas", [])) == 1  # se creó la tarea
    assert db.tablas.get("eventos", []) == []      # NUNCA un evento
