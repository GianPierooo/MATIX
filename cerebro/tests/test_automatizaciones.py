"""Automatizaciones (proactividad v1): funciones puras, CRUD por tool y el
disparo del scheduler (con tiempo y FCM mockeados, sin BD real)."""
from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

import pytest

from app.matix import automatizaciones as au
from app.matix import tools

UTC = timezone.utc


# ── Fake DB en memoria (sin Supabase) ───────────────────────────────


class FakeDB:
    def __init__(self) -> None:
        self.t: dict[str, list[dict]] = {}

    async def list(self, table, *, order=None, limit=None, filters=None, raw_filters=None):
        rows = list(self.t.get(table, []))
        if filters:
            for k, v in filters.items():
                rows = [r for r in rows if str(r.get(k)) == str(v)]
        return rows

    async def insert(self, table, payload):
        row = {"id": str(uuid.uuid4()), **payload}
        self.t.setdefault(table, []).append(row)
        return row

    async def update(self, table, _id, payload):
        for r in self.t.get(table, []):
            if r["id"] == _id:
                r.update(payload)
                return r
        return None

    async def delete(self, table, _id):
        self.t[table] = [r for r in self.t.get(table, []) if r["id"] != _id]

    async def get(self, table, _id):
        for r in self.t.get(table, []):
            if r["id"] == _id:
                return r
        return None


# ── Funciones puras ─────────────────────────────────────────────────


def test_proxima_diaria_hoy_y_manana():
    # 06:00 Lima (= 11:00 UTC). Hora 7 aún no pasó → hoy 07:00 Lima (12:00 UTC).
    desde = datetime(2026, 6, 3, 11, 0, tzinfo=UTC)
    p = au.proxima_ocurrencia("diaria", 7, 0, None, desde=desde)
    assert p == datetime(2026, 6, 3, 12, 0, tzinfo=UTC)
    # 08:00 Lima (13:00 UTC). Hora 7 ya pasó → mañana 07:00 Lima.
    desde2 = datetime(2026, 6, 3, 13, 0, tzinfo=UTC)
    p2 = au.proxima_ocurrencia("diaria", 7, 0, None, desde=desde2)
    assert p2 == datetime(2026, 6, 4, 12, 0, tzinfo=UTC)


def test_proxima_semanal_proximo_dia():
    # 2026-06-03 es miércoles (ISO 3). Pido lunes (1) → el lunes siguiente 08-06.
    desde = datetime(2026, 6, 3, 13, 0, tzinfo=UTC)  # mié 08:00 Lima
    p = au.proxima_ocurrencia("semanal", 9, 30, 1, desde=desde)
    assert p.astimezone(au.LIMA).isoweekday() == 1
    assert p.astimezone(au.LIMA).strftime("%H:%M") == "09:30"
    assert p.astimezone(au.LIMA).date() == datetime(2026, 6, 8).date()


def test_seleccionar_due_dispara_avanza_y_ignora():
    ahora = datetime(2026, 6, 3, 12, 0, tzinfo=UTC)
    autos = [
        # vencida hace 1 min, activa → disparar
        {"id": "a", "activa": True, "recurrencia": "diaria", "hora": 7,
         "proxima_ejecucion": (ahora - timedelta(minutes=1)).strftime("%Y-%m-%dT%H:%M:%SZ")},
        # futura → nada
        {"id": "b", "activa": True, "recurrencia": "diaria", "hora": 9,
         "proxima_ejecucion": (ahora + timedelta(hours=1)).strftime("%Y-%m-%dT%H:%M:%SZ")},
        # vencida hace 3 h (> ventana) → avanzar sin disparar
        {"id": "c", "activa": True, "recurrencia": "diaria", "hora": 6,
         "proxima_ejecucion": (ahora - timedelta(hours=3)).strftime("%Y-%m-%dT%H:%M:%SZ")},
        # inactiva → ignorar
        {"id": "d", "activa": False, "recurrencia": "diaria", "hora": 7,
         "proxima_ejecucion": (ahora - timedelta(minutes=1)).strftime("%Y-%m-%dT%H:%M:%SZ")},
        # sin proxima → avanzar
        {"id": "e", "activa": True, "recurrencia": "diaria", "hora": 7,
         "proxima_ejecucion": None},
    ]
    disparar, avanzar = au.seleccionar_due(autos, ahora)
    assert {x["id"] for x in disparar} == {"a"}
    assert {x["id"] for x in avanzar} == {"c", "e"}


# ── CRUD por la tool ────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_crear_listar_eliminar_por_tool():
    db = FakeDB()
    # crear
    r = await tools.ejecutar_tool(
        db,
        "crear_automatizacion",
        {
            "descripcion": "revisar mis tareas",
            "recurrencia": "diaria",
            "hora": 7,
            "tipo": "recordatorio",
            "accion": "Revisa tus tareas del día.",
        },
    )
    assert r["ok"], r
    aid = r["datos"]["id"]
    assert "cada día a las 07:00" in r["datos"]["horario"]
    assert len(db.t["automatizaciones"]) == 1
    assert db.t["automatizaciones"][0]["proxima_ejecucion"]  # se calculó

    # listar
    r2 = await tools.ejecutar_tool(db, "listar_automatizaciones", {})
    assert r2["ok"] and r2["datos"]["total"] == 1
    assert r2["datos"]["automatizaciones"][0]["id"] == aid

    # eliminar
    r3 = await tools.ejecutar_tool(
        db, "eliminar_automatizacion", {"automatizacion_id": aid}
    )
    assert r3["ok"] and r3["datos"]["eliminada"] is True
    assert db.t["automatizaciones"] == []


@pytest.mark.asyncio
async def test_crear_semanal_exige_dia():
    db = FakeDB()
    r = await tools.ejecutar_tool(
        db,
        "crear_automatizacion",
        {
            "descripcion": "resumen semanal",
            "recurrencia": "semanal",  # sin dia_semana
            "hora": 9,
            "tipo": "accion_ia",
            "accion": "resume mi semana",
        },
    )
    assert r["ok"] is False
    assert r["tipo"] == "validacion"


# ── El scheduler dispara una automatización a su hora ───────────────


@pytest.mark.asyncio
async def test_scheduler_dispara_recordatorio_y_reprograma(monkeypatch):
    ahora = datetime(2026, 6, 3, 12, 0, tzinfo=UTC)
    db = FakeDB()
    venc = (ahora - timedelta(minutes=1)).strftime("%Y-%m-%dT%H:%M:%SZ")
    db.t["automatizaciones"] = [
        {
            "id": "x1",
            "descripcion": "revisar tareas",
            "recurrencia": "diaria",
            "hora": 7,
            "minuto": 0,
            "dia_semana": None,
            "tipo": "recordatorio",
            "accion": "Revisa tus tareas.",
            "activa": True,
            "proxima_ejecucion": venc,
        }
    ]
    db.t["device_tokens"] = [{"id": "t1", "token": "TOKEN_FAKE"}]

    enviados = []

    def fake_push(token, *, titulo, cuerpo, data=None):
        enviados.append({"token": token, "titulo": titulo, "cuerpo": cuerpo})
        return "msgid"

    monkeypatch.setattr(au, "enviar_push", fake_push)

    res = await au.revisar_automatizaciones(db, ahora=ahora)
    assert res["automatizaciones"] == 1
    assert len(enviados) == 1
    assert enviados[0]["cuerpo"] == "Revisa tus tareas."
    assert "Recordatorio" in enviados[0]["titulo"]
    # reprogramó la próxima al futuro (mañana 07:00).
    nueva = au._parse(db.t["automatizaciones"][0]["proxima_ejecucion"])
    assert nueva > ahora


@pytest.mark.asyncio
async def test_scheduler_no_dispara_futura(monkeypatch):
    ahora = datetime(2026, 6, 3, 12, 0, tzinfo=UTC)
    db = FakeDB()
    futuro = (ahora + timedelta(hours=2)).strftime("%Y-%m-%dT%H:%M:%SZ")
    db.t["automatizaciones"] = [
        {"id": "x2", "descripcion": "x", "recurrencia": "diaria", "hora": 14,
         "minuto": 0, "dia_semana": None, "tipo": "recordatorio", "accion": "luego",
         "activa": True, "proxima_ejecucion": futuro}
    ]
    db.t["device_tokens"] = [{"id": "t1", "token": "TOK"}]
    enviados = []
    monkeypatch.setattr(au, "enviar_push", lambda *a, **k: enviados.append(1))
    res = await au.revisar_automatizaciones(db, ahora=ahora)
    assert res["automatizaciones"] == 0
    assert enviados == []
