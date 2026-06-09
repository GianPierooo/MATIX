"""Capa de comandos (2.0 · Fase 2) — Universidad.

Verifica que la sección Universidad sigue el patrón de Fase 1: registro de
comandos con handler único, y que la UI (router) y la IA (tool) enrutan al
MISMO comando. Cubre cursos, sesiones de clase (incluida una clase RECURRENTE)
y evaluaciones (CRUD + lectura). FakeDB en memoria, sin red.
"""
from __future__ import annotations

import asyncio

from app.comandos import registro
from app.matix import tools

_CURSO = "22222222-2222-2222-2222-222222222222"
_SESION = "33333333-3333-3333-3333-333333333333"
_EVAL = "44444444-4444-4444-4444-444444444444"


class FakeDB:
    """Postgrest mínimo: get/list/insert/update/delete por tabla."""

    def __init__(self, tablas: dict[str, list[dict]] | None = None) -> None:
        self.tablas: dict[str, list[dict]] = tablas or {}
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
        return fila

    async def update(self, tabla, id_, payload):
        for f in self.tablas.get(tabla, []):
            if str(f.get("id")) == str(id_):
                f.update(payload)
                return f
        return None

    async def delete(self, tabla, id_):
        antes = len(self.tablas.get(tabla, []))
        self.tablas[tabla] = [
            f for f in self.tablas.get(tabla, []) if str(f.get("id")) != str(id_)
        ]
        return len(self.tablas.get(tabla, [])) < antes


def _rows(db: FakeDB, tabla: str) -> list[dict]:
    return db.tablas.get(tabla, [])


# ── El registro ──────────────────────────────────────────────────────────────


def test_registro_tiene_comandos_universidad():
    for n in (
        "crear_curso", "editar_curso", "eliminar_curso", "consultar_cursos",
        "crear_sesion_clase", "crear_sesiones_clase", "editar_sesion_clase",
        "eliminar_sesion_clase", "consultar_sesiones_clase",
        "crear_evaluacion", "editar_evaluacion", "eliminar_evaluacion",
        "consultar_evaluaciones",
    ):
        assert registro.existe(n), n
    assert registro.get("crear_curso").riesgo.value == "consecuente"
    assert registro.get("consultar_cursos").riesgo.value == "segura"
    assert "cursos" in registro.get("crear_curso").tablas


# ── Cursos ───────────────────────────────────────────────────────────────────


def test_crear_curso_inserta():
    db = FakeDB()
    r = asyncio.run(registro.ejecutar(db, "crear_curso", {"nombre": "Cálculo I"}))
    assert r["ok"] and r["datos"]["nombre"] == "Cálculo I"
    assert len(_rows(db, "cursos")) == 1


def test_crear_curso_validacion():
    r = asyncio.run(registro.ejecutar(FakeDB(), "crear_curso", {"nombre": ""}))
    assert r["ok"] is False and r["tipo"] == "validacion"


def test_editar_curso():
    db = FakeDB({"cursos": [{"id": _CURSO, "nombre": "Cálculo"}]})
    r = asyncio.run(registro.ejecutar(
        db, "editar_curso", {"curso_id": _CURSO, "profesor": "Gauss"}))
    assert r["ok"] and _rows(db, "cursos")[0]["profesor"] == "Gauss"


def test_eliminar_curso_borra_duro():
    db = FakeDB({"cursos": [{"id": _CURSO, "nombre": "Cálculo"}]})
    r = asyncio.run(registro.ejecutar(db, "eliminar_curso", {"curso_id": _CURSO}))
    assert r["ok"] and r["datos"]["nombre"] == "Cálculo"
    assert _rows(db, "cursos") == []  # borrado duro


def test_consultar_cursos():
    db = FakeDB({"cursos": [
        {"id": _CURSO, "nombre": "Física", "profesor": "Newton"},
    ]})
    r = asyncio.run(registro.ejecutar(db, "consultar_cursos", {}))
    assert r["ok"] and r["datos"]["total"] == 1
    assert r["datos"]["cursos"][0]["nombre"] == "Física"


# ── Sesiones de clase (recurrencia = N filas, una por día) ────────────────────


def test_crear_sesion_clase_un_dia():
    db = FakeDB()
    r = asyncio.run(registro.ejecutar(db, "crear_sesion_clase", {
        "curso_id": _CURSO, "dia_semana": 0,
        "hora_inicio": "08:00", "hora_fin": "10:00",
    }))
    assert r["ok"] and len(_rows(db, "sesiones_clase")) == 1


def test_clase_recurrente_crea_una_sesion_por_dia():
    """«Cálculo lunes y miércoles 8-10» → dias_semana=[0, 2] → dos sesiones a la
    misma hora. La recurrencia del horario NO usa la repetición del calendario."""
    db = FakeDB()
    r = asyncio.run(registro.ejecutar(db, "crear_sesiones_clase", {
        "curso_id": _CURSO, "dias_semana": [0, 2],
        "hora_inicio": "08:00", "hora_fin": "10:00", "ubicacion": "A-101",
    }))
    assert r["ok"] and r["datos"]["total"] == 2
    sesiones = _rows(db, "sesiones_clase")
    assert len(sesiones) == 2
    assert {s["dia_semana"] for s in sesiones} == {0, 2}
    assert all(s["hora_inicio"] == "08:00:00" for s in sesiones)


def test_clase_recurrente_sin_dias_es_validacion():
    r = asyncio.run(registro.ejecutar(FakeDB(), "crear_sesiones_clase", {
        "curso_id": _CURSO, "dias_semana": [],
        "hora_inicio": "08:00", "hora_fin": "10:00",
    }))
    assert r["ok"] is False and r["tipo"] == "validacion"


def test_consultar_sesiones_filtra_por_curso():
    db = FakeDB({
        "cursos": [{"id": _CURSO, "nombre": "Cálculo"}],
        "sesiones_clase": [
            {"id": _SESION, "curso_id": _CURSO, "dia_semana": 0,
             "hora_inicio": "08:00:00", "hora_fin": "10:00:00"},
            {"id": "otra", "curso_id": "99999999-9999-9999-9999-999999999999",
             "dia_semana": 1, "hora_inicio": "09:00:00", "hora_fin": "11:00:00"},
        ],
    })
    r = asyncio.run(registro.ejecutar(
        db, "consultar_sesiones_clase", {"curso_id": _CURSO}))
    assert r["ok"] and r["datos"]["total"] == 1
    assert r["datos"]["sesiones"][0]["curso"] == "Cálculo"
    assert r["datos"]["sesiones"][0]["dia"] == "lunes"


# ── Evaluaciones ──────────────────────────────────────────────────────────────


def test_crear_evaluacion():
    db = FakeDB()
    r = asyncio.run(registro.ejecutar(db, "crear_evaluacion", {
        "curso_id": _CURSO, "titulo": "Parcial 1", "tipo": "examen",
        "fecha": "2026-06-15T10:00:00-05:00", "peso": 30,
    }))
    assert r["ok"] and r["datos"]["titulo"] == "Parcial 1"
    assert len(_rows(db, "evaluaciones")) == 1


def test_crear_evaluacion_tipo_invalido_es_validacion():
    r = asyncio.run(registro.ejecutar(FakeDB(), "crear_evaluacion", {
        "curso_id": _CURSO, "titulo": "X", "tipo": "quiz",  # no permitido
        "fecha": "2026-06-15T10:00:00-05:00",
    }))
    assert r["ok"] is False and r["tipo"] == "validacion"


def test_consultar_evaluaciones_filtra_por_rango():
    db = FakeDB({
        "cursos": [{"id": _CURSO, "nombre": "Física"}],
        "evaluaciones": [
            {"id": _EVAL, "curso_id": _CURSO, "titulo": "Parcial",
             "tipo": "examen", "fecha": "2026-06-10T10:00:00-05:00"},
            {"id": "tarde", "curso_id": _CURSO, "titulo": "Final",
             "tipo": "examen", "fecha": "2026-07-20T10:00:00-05:00"},
        ],
    })
    r = asyncio.run(registro.ejecutar(db, "consultar_evaluaciones", {
        "desde": "2026-06-08", "hasta": "2026-06-14",
    }))
    assert r["ok"] and r["datos"]["total"] == 1
    assert r["datos"]["evaluaciones"][0]["titulo"] == "Parcial"
    assert r["datos"]["evaluaciones"][0]["curso"] == "Física"


# ── Paridad UI ↔ IA: misma ruta canónica ─────────────────────────────────────


def test_ui_y_ia_crean_curso_por_el_mismo_comando():
    db_ui = FakeDB()
    db_ia = FakeDB()
    # UI: lo que hace el router.
    r_ui = asyncio.run(registro.ejecutar(db_ui, "crear_curso", {"nombre": "Química"}, origen="ui"))
    # IA: la tool envuelve el MISMO comando.
    r_ia = asyncio.run(tools.ejecutar_tool(db_ia, "crear_curso", {"nombre": "Química"}))
    assert r_ui["ok"] and r_ia["ok"]
    assert _rows(db_ui, "cursos")[0]["nombre"] == _rows(db_ia, "cursos")[0]["nombre"] == "Química"
    assert r_ia["datos"]["nombre"] == "Química"  # envelope del LLM


def test_ui_y_ia_crean_evaluacion_por_el_mismo_comando():
    db_ui = FakeDB()
    db_ia = FakeDB()
    args = {
        "curso_id": _CURSO, "titulo": "Entrega 1", "tipo": "entrega",
        "fecha": "2026-06-20T23:59:00-05:00",
    }
    r_ui = asyncio.run(registro.ejecutar(db_ui, "crear_evaluacion", args, origen="ui"))
    r_ia = asyncio.run(tools.ejecutar_tool(db_ia, "crear_evaluacion", dict(args)))
    assert r_ui["ok"] and r_ia["ok"]
    assert _rows(db_ui, "evaluaciones")[0]["titulo"] == _rows(db_ia, "evaluaciones")[0]["titulo"]


def test_ia_consulta_cursos_via_tool():
    db = FakeDB({"cursos": [{"id": _CURSO, "nombre": "Álgebra"}]})
    r = asyncio.run(tools.ejecutar_tool(db, "consultar_cursos", {}))
    assert r["ok"] and r["datos"]["cursos"][0]["nombre"] == "Álgebra"


# ── Seguridad: el borrado por la IA exige confirmación ───────────────────────


def test_ia_eliminar_curso_pide_confirmacion():
    db = FakeDB({"cursos": [{"id": _CURSO, "nombre": "Cálculo"}]})
    # Sin confirmado=true → NO borra; pide confirmación.
    r = asyncio.run(tools.ejecutar_tool(db, "eliminar_curso", {"curso_id": _CURSO}))
    assert r["ok"] is False and r["tipo"] == "requiere_confirmacion"
    assert len(_rows(db, "cursos")) == 1  # sigue ahí
    # Con confirmado=true → borra.
    r2 = asyncio.run(tools.ejecutar_tool(
        db, "eliminar_curso", {"curso_id": _CURSO, "confirmado": True}))
    assert r2["ok"] and _rows(db, "cursos") == []
