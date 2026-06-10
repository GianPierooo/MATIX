"""Capa 8 — orquestación del motor de proactividad: que cada detector de RIESGO
dispare en su condición (vía `_candidatos`), que la dosificación (cap diario +
dedup por tema + silencio) frene, y que los TRIGGERS no toquen el LLM. FakeDB en
memoria, sin red ni FCM.
"""
from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone

from app.matix import planificador_diario
from app.matix import proactividad as p

_UTC = timezone.utc
# 2026-06-09 15:00 UTC = 10:00 Lima (martes) — dentro de la ventana, no silencio.
AHORA = datetime(2026, 6, 9, 15, 0, tzinfo=_UTC)
LOCAL = AHORA.astimezone(p.LIMA)


class FakeDB:
    def __init__(self, tablas=None):
        self.tablas = tablas or {}
        self.inserts = []

    async def list(self, tabla, *, filters=None, raw_filters=None, order=None, limit=None):
        filas = list(self.tablas.get(tabla, []))
        if filters:
            for k, v in filters.items():
                filas = [f for f in filas if f.get(k) == v]
        return filas

    async def get(self, tabla, id_):
        for f in self.tablas.get(tabla, []):
            if str(f.get("id")) == str(id_):
                return f
        return None

    async def insert(self, tabla, row):
        fila = {"id": row.get("id") or f"{tabla}-{len(self.inserts)}", **row}
        self.tablas.setdefault(tabla, []).append(fila)
        self.inserts.append((tabla, row))
        return fila

    async def update(self, tabla, id_, payload):
        for f in self.tablas.get(tabla, []):
            if str(f.get("id")) == str(id_):
                f.update(payload)
                return f
        return None


_PLAN_VACIO = {"bloques": [], "fuera": [], "duerme": "23:00", "sugerencias": [], "huecos": []}


def _patch_plan(monkeypatch, plan):
    from app.matix import horario

    async def fake_plan(db, *, ahora=None, desde_ahora=False):
        return plan

    monkeypatch.setattr(horario, "plan_de_hoy_data", fake_plan)


def _tipos(candidatos):
    return {c["tipo"] for c in candidatos}


# Nivel "equilibrado": no incluye el gatillo "hueco" (evita ruido en aislamiento).
_PAR = p.params_nivel("equilibrado")


# ── Cada detector de riesgo dispara vía _candidatos en SU condición ──────────


def test_detector_dia_sobrecargado_dispara_con_fuera_de_trabajo(monkeypatch):
    plan = {**_PLAN_VACIO, "fuera": [
        {"titulo": "Sprint", "tipo": "trabajo", "motivo": "no entró"},
        {"titulo": "Práctica", "tipo": "skill", "motivo": "no entró"},  # NO cuenta
    ]}
    _patch_plan(monkeypatch, plan)
    db = FakeDB()
    cands = asyncio.run(p._candidatos(db, ahora=AHORA, local=LOCAL, cfg={}, par=_PAR))
    assert "sobrecarga" in _tipos(cands)
    # Sin trabajo recortado → no dispara.
    _patch_plan(monkeypatch, _PLAN_VACIO)
    cands2 = asyncio.run(p._candidatos(db, ahora=AHORA, local=LOCAL, cfg={}, par=_PAR))
    assert "sobrecarga" not in _tipos(cands2)


def test_detector_estancado_temprano_dispara_en_banda(monkeypatch):
    _patch_plan(monkeypatch, _PLAN_VACIO)
    viejo = (AHORA - timedelta(days=4)).isoformat()
    fresco = (AHORA - timedelta(days=1)).isoformat()
    db = FakeDB({"proyectos": [
        {"id": "p1", "nombre": "OneXotic", "estado": "activo", "es_skill": False,
         "ultima_actividad_en": viejo},
        {"id": "p2", "nombre": "Fresco", "estado": "activo", "es_skill": False,
         "ultima_actividad_en": fresco},
    ]})
    cands = asyncio.run(p._candidatos(db, ahora=AHORA, local=LOCAL, cfg={}, par=_PAR))
    estancados = [c for c in cands if c["tipo"] == "estancado"]
    assert len(estancados) == 1 and estancados[0]["payload"] == "proyecto:p1"


def test_detector_evaluacion_sin_estudio(monkeypatch):
    _patch_plan(monkeypatch, _PLAN_VACIO)
    fecha_eval = (LOCAL.date() + timedelta(days=3)).isoformat() + "T10:00:00-05:00"
    # Sin tareas del curso → en riesgo.
    db = FakeDB({"evaluaciones": [
        {"id": "e1", "titulo": "Parcial 1", "curso_id": "c1", "fecha": fecha_eval},
    ]})
    cands = asyncio.run(p._candidatos(db, ahora=AHORA, local=LOCAL, cfg={}, par=_PAR))
    assert "eval_estudio" in _tipos(cands)
    # Con una tarea del curso (estudio agendado) → NO molesta.
    db2 = FakeDB({
        "evaluaciones": [{"id": "e1", "titulo": "Parcial 1", "curso_id": "c1", "fecha": fecha_eval}],
        "tareas": [{"id": "t1", "titulo": "Estudiar", "curso_id": "c1", "completada": False}],
    })
    cands2 = asyncio.run(p._candidatos(db2, ahora=AHORA, local=LOCAL, cfg={}, par=_PAR))
    assert "eval_estudio" not in _tipos(cands2)


def test_detector_skill_descuidada(monkeypatch):
    _patch_plan(monkeypatch, _PLAN_VACIO)
    viejo = (AHORA - timedelta(days=9)).isoformat()
    db = FakeDB({"proyectos": [
        {"id": "s1", "nombre": "Inglés", "estado": "activo", "es_skill": True,
         "ultima_actividad_en": viejo},
    ]})
    cands = asyncio.run(p._candidatos(db, ahora=AHORA, local=LOCAL, cfg={}, par=_PAR))
    assert "skill_descuidada" in _tipos(cands)
    # Skill practicada hace poco → no molesta.
    db2 = FakeDB({"proyectos": [
        {"id": "s1", "nombre": "Inglés", "estado": "activo", "es_skill": True,
         "ultima_actividad_en": (AHORA - timedelta(days=2)).isoformat()},
    ]})
    cands2 = asyncio.run(p._candidatos(db2, ahora=AHORA, local=LOCAL, cfg={}, par=_PAR))
    assert "skill_descuidada" not in _tipos(cands2)


# ── DETERMINISMO: la DETECCIÓN (_candidatos) no toca el LLM ───────────────────


def test_candidatos_no_llaman_al_modelo(monkeypatch):
    """El trigger es puro cálculo: si la detección tocara el LLM, esto explota."""
    from app.matix import llm

    def bomba(*a, **k):
        raise AssertionError("¡un detector de proactividad tocó el LLM!")

    for n in ("responder", "responder_con_tools"):
        if hasattr(llm, n):
            monkeypatch.setattr(llm, n, bomba)
    _patch_plan(monkeypatch, {**_PLAN_VACIO, "fuera": [{"titulo": "X", "tipo": "trabajo", "motivo": "x"}]})
    db = FakeDB({"evaluaciones": [], "proyectos": []})
    cands = asyncio.run(p._candidatos(db, ahora=AHORA, local=LOCAL, cfg={}, par=_PAR))
    assert "sobrecarga" in _tipos(cands)  # detectó sin tocar el modelo


# ── DOSIFICACIÓN: cap diario, dedup por tema, silencio ───────────────────────


def _db_listo():
    """FakeDB con proactividad activa y un token; sin silencio (config_nudges vacío)."""
    return FakeDB({
        "config_proactividad": [{"id": "c", "activo": True, "nivel": "exigente", "lead_libre_min": 30}],
        "config_nudges": [],
        "device_tokens": [{"token": "tok"}],
        "set_diario_items": [],
        "proactividad_enviados": [],
    })


def _stub_candidatos(monkeypatch, candidatos):
    async def fake(db, **kw):
        return list(candidatos)
    monkeypatch.setattr(p, "_candidatos", fake)


def _stub_push_ok(monkeypatch, registro):
    async def fake_push(db, tokens, *, titulo, cuerpo, payload):
        registro.append((titulo, payload))
        return True
    monkeypatch.setattr(planificador_diario, "_push", fake_push)


_CAND_A = {"tipo": "sobrecarga", "clave": "sobrecarga:2026-06-09", "titulo": "Cargado",
           "cuerpo": "x", "payload": "rollover", "urgencia": 3, "oportunidad": 3, "relevancia": 3}
_CAND_B = {"tipo": "skill_descuidada", "clave": "skill_descuidada:s1", "titulo": "Skill",
           "cuerpo": "y", "payload": "proyecto:s1", "urgencia": 1, "oportunidad": 2, "relevancia": 1}


def test_tick_manda_uno_el_de_mayor_puntaje(monkeypatch):
    enviados = []
    _stub_candidatos(monkeypatch, [_CAND_B, _CAND_A])
    _stub_push_ok(monkeypatch, enviados)
    db = _db_listo()
    r = asyncio.run(p.revisar_proactividad(db, ahora=AHORA))
    assert r == {"proactividad": 1, "tipo": "sobrecarga"}  # el de más puntaje
    assert len(enviados) == 1
    assert db.tablas["proactividad_enviados"]  # quedó registrado para dedup


def test_tick_dedup_no_repite_el_mismo_tema(monkeypatch):
    enviados = []
    _stub_candidatos(monkeypatch, [_CAND_A])
    _stub_push_ok(monkeypatch, enviados)
    db = _db_listo()
    # Ya se mandó hoy ese tema.
    db.tablas["proactividad_enviados"] = [{"clave": _CAND_A["clave"], "fecha": LOCAL.date().isoformat()}]
    r = asyncio.run(p.revisar_proactividad(db, ahora=AHORA))
    assert r.get("sin_candidatos") and not enviados  # dedup lo filtró


def test_tick_respeta_el_cap_diario(monkeypatch):
    enviados = []
    _stub_candidatos(monkeypatch, [_CAND_A])
    _stub_push_ok(monkeypatch, enviados)
    db = _db_listo()
    # Exigente: tope 7. Lleno el cupo del día con temas distintos.
    db.tablas["proactividad_enviados"] = [
        {"clave": f"otro:{i}", "fecha": LOCAL.date().isoformat()} for i in range(7)
    ]
    r = asyncio.run(p.revisar_proactividad(db, ahora=AHORA))
    assert r.get("tope") and not enviados


def test_tick_respeta_el_silencio_nocturno(monkeypatch):
    enviados = []
    _stub_candidatos(monkeypatch, [_CAND_A])
    _stub_push_ok(monkeypatch, enviados)
    db = _db_listo()
    # config_nudges con silencio que cubre la hora actual (10:00 Lima).
    db.tablas["config_nudges"] = [{"silencio_inicio": 8, "silencio_fin": 12, "disponibilidad": {}}]
    r = asyncio.run(p.revisar_proactividad(db, ahora=AHORA))
    assert r.get("fuera_de_ventana") and not enviados


def test_tick_baja_el_tono_si_se_ignora(monkeypatch):
    """Si se mandaron varios y NO hubo acción, el tope se recorta (no sube)."""
    enviados = []
    _stub_candidatos(monkeypatch, [_CAND_A])
    _stub_push_ok(monkeypatch, enviados)
    db = _db_listo()
    # 4 enviados hoy, 0 acciones → tope_ajustado_por_ritmo(7,4,0)=2 → ya pasó el cap.
    db.tablas["proactividad_enviados"] = [
        {"clave": f"otro:{i}", "fecha": LOCAL.date().isoformat()} for i in range(4)
    ]
    r = asyncio.run(p.revisar_proactividad(db, ahora=AHORA))
    assert r.get("tope") and not enviados  # con ritmo bajo, 4 ya supera el tope recortado (2)
