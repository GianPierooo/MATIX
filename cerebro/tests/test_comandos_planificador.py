"""Capa de comandos (2.0 · Fase 5) — Planificador / "Tu día".

Verifica que el bucle diario (rollover, despertar, bloques, set) pasa por el
registro, que la UI y la IA enrutan al MISMO comando, que D3 quedó en una sola
ruta, que completar un bloque sigue siendo consistente con Fases 1/4, y —lo
crítico— que el DETERMINISMO se preserva: estos caminos NO tocan el LLM.
FakeDB en memoria, sin red, sin modelo.
"""
from __future__ import annotations

import asyncio

from app.comandos import planificador as cmd_planificador
from app.comandos import registro
from app.matix import rollover
from app.matix import tools

_T = "11111111-1111-1111-1111-111111111111"


class FakeDB:
    def __init__(self, tablas: dict[str, list[dict]] | None = None) -> None:
        self.tablas: dict[str, list[dict]] = tablas or {}
        self.updates: list[tuple[str, str, dict]] = []
        self.inserts: list[tuple[str, dict]] = []
        self._n = 0

    async def get(self, tabla, id_):
        for f in self.tablas.get(tabla, []):
            if str(f.get("id")) == str(id_):
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
        self.updates.append((tabla, str(id_), payload))
        for f in self.tablas.get(tabla, []):
            if str(f.get("id")) == str(id_):
                f.update(payload)
                return f
        return {"id": id_, **payload}

    async def delete(self, tabla, id_):
        antes = len(self.tablas.get(tabla, []))
        self.tablas[tabla] = [f for f in self.tablas.get(tabla, []) if str(f.get("id")) != str(id_)]
        return len(self.tablas.get(tabla, [])) < antes


# ── El registro ──────────────────────────────────────────────────────────────


def test_registro_tiene_comandos_planificador():
    for n in ("proponer_set_dia", "ver_set_dia", "aceptar_set_dia", "saltar_item_set",
              "agendar_bloque", "saltar_bloque", "completar_bloque", "marcar_despertar",
              "plan_de_hoy", "replanificar_dia", "proponer_rollover", "aplicar_rollover"):
        assert registro.existe(n), n
    # Lecturas marcadas SEGURA; las que mutan, CONSECUENTE.
    assert registro.get("plan_de_hoy").riesgo.value == "segura"
    assert registro.get("proponer_rollover").riesgo.value == "segura"
    assert registro.get("aplicar_rollover").riesgo.value == "consecuente"


# ── Rollover ─────────────────────────────────────────────────────────────────


def test_aplicar_rollover_soltar():
    db = FakeDB({"tareas": [{"id": _T, "titulo": "X", "completada": False}]})
    r = asyncio.run(registro.ejecutar(db, "aplicar_rollover", {"tarea_id": _T, "decision": "soltar"}))
    assert r["ok"] and r["datos"]["decision"] == "soltada"
    assert db.tablas["tareas"][0].get("eliminado_en")


def test_posponer_se_mapea_a_otro_dia(monkeypatch):
    """«posponer» es el nombre humano de «otro_dia»: el comando lo traduce antes
    de delegar al rollover determinista."""
    capturado = {}

    async def fake_aplicar(db, *, tarea_id, decision, **kw):
        capturado["decision"] = decision
        return {"ok": True, "decision": decision}

    monkeypatch.setattr(rollover, "aplicar_rollover", fake_aplicar)
    asyncio.run(registro.ejecutar(
        FakeDB(), "aplicar_rollover", {"tarea_id": _T, "decision": "posponer"}))
    assert capturado["decision"] == "otro_dia"


def test_aplicar_rollover_decision_invalida():
    r = asyncio.run(registro.ejecutar(
        FakeDB(), "aplicar_rollover", {"tarea_id": _T, "decision": "quemar"}))
    assert r["ok"] is False and r["tipo"] == "validacion"


def test_aplicar_rollover_sin_tarea_preserva_contrato():
    """El endpoint /rollover/decidir devolvía el dict con ok=False + flags (200);
    el comando NO lo convierte en error HTTP: lo pasa tal cual."""
    db = FakeDB({"tareas": []})
    r = asyncio.run(registro.ejecutar(db, "aplicar_rollover", {"tarea_id": _T, "decision": "aceptar"}))
    assert r["ok"] is True  # el comando corrió
    assert r["datos"]["ok"] is False and r["datos"].get("no_existe")  # resultado honesto


def test_ui_y_ia_aplican_rollover_por_el_mismo_comando():
    db_ui = FakeDB({"tareas": [{"id": _T, "titulo": "X", "completada": False}]})
    db_ia = FakeDB({"tareas": [{"id": _T, "titulo": "X", "completada": False}]})
    r_ui = asyncio.run(registro.ejecutar(db_ui, "aplicar_rollover", {"tarea_id": _T, "decision": "soltar"}, origen="ui"))
    r_ia = asyncio.run(tools.ejecutar_tool(db_ia, "aplicar_rollover", {"tarea_id": _T, "decision": "soltar"}))
    assert r_ui["ok"] and r_ia["ok"]
    assert db_ui.tablas["tareas"][0].get("eliminado_en")
    assert db_ia.tablas["tareas"][0].get("eliminado_en")


# ── Set + bloques ────────────────────────────────────────────────────────────


def test_saltar_item_set():
    db = FakeDB({"set_diario_items": [{"id": "s1", "estado": "propuesto"}]})
    r = asyncio.run(registro.ejecutar(db, "saltar_item_set", {"item_id": "s1"}))
    assert r["ok"] and db.tablas["set_diario_items"][0]["estado"] == "saltado"


def test_completar_bloque_por_comando_completa_tarea_d5():
    """Completar un bloque atado a una tarea enruta a completar_tarea (Fase 1):
    repetición + sync. Mismo estado que por checkbox/IA."""
    db = FakeDB({"tareas": [{
        "id": _T, "titulo": "Gym", "completada": False, "prioridad": "media",
        "repeticion": "diaria", "vence_en": "2026-06-10T10:00:00+00:00",
    }]})
    r = asyncio.run(registro.ejecutar(db, "completar_bloque", {"tarea_id": _T}))
    assert r["ok"]
    orig = next(t for t in db.tablas["tareas"] if t["id"] == _T)
    assert orig["completada"] is True
    assert len(db.tablas["tareas"]) == 2  # se creó la repetición (D5 intacto)


def test_d3_agendar_bloque_crea_tarea_nunca_evento():
    """D3: la ruta canónica de «agregar al día» (agendar_bloque) crea una TAREA
    con su bloque, NUNCA un evento pelado."""
    db = FakeDB()
    bloques = [{"titulo": "Práctica: Inglés", "inicio": "10:00", "fin": "10:30",
                "proyecto_id": "skill-ing"}]
    r = asyncio.run(registro.ejecutar(db, "agendar_bloque", {"bloques": bloques}))
    assert r["ok"] and r["datos"]["agendadas"] == 1
    assert len(db.tablas.get("tareas", [])) == 1
    assert db.tablas.get("eventos", []) == []  # NUNCA un evento


def test_agendar_bloque_engancha_tarea_existente_sin_evento():
    db = FakeDB()
    bloques = [{"titulo": "Sprint", "inicio": "08:00", "fin": "09:30", "tarea_id": "t1"}]
    r = asyncio.run(registro.ejecutar(db, "agendar_bloque", {"bloques": bloques}))
    assert r["ok"] and r["datos"]["agendadas"] == 1
    assert any(t == "tareas" and id_ == "t1" and "bloque_inicio" in p
               for t, id_, p in db.updates)
    assert db.tablas.get("eventos", []) == []


# ── Despertar (rundown determinista) ─────────────────────────────────────────


def test_marcar_despertar_es_determinista_y_da_plan():
    db = FakeDB()
    r = asyncio.run(registro.ejecutar(db, "marcar_despertar", {}))
    assert r["ok"]
    assert r["datos"].get("despierta_hoy")  # ancla de hoy registrada
    assert "plan" in r["datos"]             # rundown calculado
    # Ancla persistida en despertar_dia (sin LLM, instantáneo).
    assert db.tablas.get("despertar_dia")


# ── DETERMINISMO: ningún camino del planificador toca el LLM ─────────────────


def test_planificador_no_importa_llm():
    """El módulo de comandos del planificador no debe referenciar el LLM: estos
    caminos son deterministas por contrato."""
    import inspect
    fuente = inspect.getsource(cmd_planificador)
    # No hay importación del módulo llm ni acceso a sus funciones (el bucle
    # diario es determinista; la mención a "llm" en el docstring no cuenta).
    assert "import llm" not in fuente
    assert "llm." not in fuente


def test_bucle_diario_corre_sin_modelo(monkeypatch):
    """Bomba: si CUALQUIER comando del bucle intentara llamar al modelo, explota.
    Verifica que rollover/despertar/agendar/completar corren SIN tocar el LLM."""
    from app.matix import llm

    def bomba(*a, **k):
        raise AssertionError("¡un camino del planificador tocó el LLM!")

    for nombre in ("responder_con_tools", "responder", "extraer_eventos_json"):
        if hasattr(llm, nombre):
            monkeypatch.setattr(llm, nombre, bomba)

    db = FakeDB({"tareas": [{"id": _T, "titulo": "X", "completada": False}]})
    asyncio.run(registro.ejecutar(db, "aplicar_rollover", {"tarea_id": _T, "decision": "soltar"}))
    asyncio.run(registro.ejecutar(FakeDB(), "marcar_despertar", {}))
    asyncio.run(registro.ejecutar(FakeDB(), "agendar_bloque", {
        "bloques": [{"titulo": "Z", "inicio": "10:00", "fin": "10:30"}]}))
    asyncio.run(registro.ejecutar(
        FakeDB({"tareas": [{"id": _T, "titulo": "Y", "completada": False}]}),
        "completar_bloque", {"tarea_id": _T}))
    # Si llegamos acá, ningún camino llamó al modelo.


# ── Post-revisión: replanificar respeta `ahora`; rollover shape para el LLM ──


def test_replanificar_respeta_ahora_del_param(monkeypatch):
    """El endpoint /horario/replanificar expone `ahora`; el comando lo debe
    pasar a plan_de_hoy_data (antes lo ignoraba y usaba la hora del servidor)."""
    from app.matix import horario as horario_mod
    capturado = {}

    async def fake_plan(db, *, ahora=None, desde_ahora=False):
        capturado["ahora"] = ahora
        capturado["desde_ahora"] = desde_ahora
        return {"bloques": []}

    monkeypatch.setattr(horario_mod, "plan_de_hoy_data", fake_plan)
    asyncio.run(registro.ejecutar(
        FakeDB(), "replanificar_dia", {"ahora": "2026-06-09T15:30:00+00:00"}))
    assert capturado["ahora"] is not None
    assert capturado["ahora"].isoformat().startswith("2026-06-09T15:30")
    assert capturado["desde_ahora"] is True


def test_replanificar_ahora_invalido_es_validacion():
    r = asyncio.run(registro.ejecutar(FakeDB(), "replanificar_dia", {"ahora": "no-es-fecha"}))
    assert r["ok"] is False and r["tipo"] == "validacion"


def test_aplicar_rollover_tool_traduce_flags_para_el_llm():
    """La tool NO debe devolver el dict anidado del comando: traduce sin_hueco/
    no_existe a un error tipado plano y el éxito a _ok plano."""
    # no_existe (tarea ausente, decision aceptar) → error tipado limpio.
    db = FakeDB({"tareas": []})
    r = asyncio.run(tools.ejecutar_tool(db, "aplicar_rollover", {"tarea_id": _T, "decision": "aceptar"}))
    assert r["ok"] is False and r["tipo"] == "no_existe"
    # Éxito (soltar) → _ok plano, sin doble anidación incomprensible.
    db2 = FakeDB({"tareas": [{"id": _T, "titulo": "X", "completada": False}]})
    r2 = asyncio.run(tools.ejecutar_tool(db2, "aplicar_rollover", {"tarea_id": _T, "decision": "soltar"}))
    assert r2["ok"] is True and r2["datos"].get("decision") == "soltada"
