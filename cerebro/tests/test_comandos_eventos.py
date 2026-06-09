"""Capa de comandos (2.0 · Fase 3) — Eventos / Calendario + recurrencia.

Verifica: crear evento (suelto y recurrente), el alcance al editar/borrar una
serie (toda_serie / solo_esta / esta_y_futuras), la consolidación de las 3 rutas
de creación (D4), la paridad UI↔IA, y que la recurrencia de CLASES y la de
EVENTOS comparten un solo motor. FakeDB en memoria, sin red.
"""
from __future__ import annotations

import asyncio
from datetime import date

from app.comandos import recurrencia, registro
from app.matix import tools

_EV = "55555555-5555-5555-5555-555555555555"
# 2026-06-01 es LUNES (isoweekday 1).
_ANCLA = "2026-06-01T08:00:00-05:00"


class FakeDB:
    def __init__(self, tablas: dict[str, list[dict]] | None = None) -> None:
        self.tablas: dict[str, list[dict]] = tablas or {}
        self._n = 0

    async def get(self, tabla, id_):
        for f in self.tablas.get(tabla, []):
            if str(f.get("id")) == str(id_):
                return f
        return None

    async def list(self, tabla, *, filters=None, raw_filters=None, order=None, limit=None):
        return list(self.tablas.get(tabla, []))

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
        self.tablas[tabla] = [f for f in self.tablas.get(tabla, []) if str(f.get("id")) != str(id_)]
        return len(self.tablas.get(tabla, [])) < antes


def _eventos(db: FakeDB) -> list[dict]:
    return db.tablas.get("eventos", [])


def _serie_semanal() -> dict:
    """Evento que se repite lunes y miércoles (ISO [1, 3]) desde el 1-jun."""
    return {
        "id": _EV, "titulo": "Gym", "inicia_en": _ANCLA,
        "termina_en": "2026-06-01T09:00:00-05:00", "todo_el_dia": False,
        "origen": "manual",
        "recurrencia_freq": "semanal", "recurrencia_dias_semana": [1, 3],
        "recurrencia_fin_tipo": "nunca",
    }


# ── El registro ──────────────────────────────────────────────────────────────


def test_registro_tiene_comandos_eventos():
    for n in ("crear_evento", "editar_evento", "eliminar_evento",
              "restaurar_evento", "consultar_eventos"):
        assert registro.existe(n), n
    assert registro.get("crear_evento").riesgo.value == "consecuente"
    assert registro.get("consultar_eventos").riesgo.value == "segura"


# ── Crear (suelto + recurrente) ──────────────────────────────────────────────


def test_crear_evento_suelto():
    db = FakeDB()
    r = asyncio.run(registro.ejecutar(db, "crear_evento", {
        "titulo": "Cita médica", "inicia_en": "2026-06-10T15:00:00-05:00",
    }))
    assert r["ok"] and not r["datos"].get("recurrencia_freq")
    assert len(_eventos(db)) == 1


def test_crear_evento_recurrente_valido():
    db = FakeDB()
    r = asyncio.run(registro.ejecutar(db, "crear_evento", {
        "titulo": "Gym", "inicia_en": _ANCLA,
        "recurrencia_freq": "semanal", "recurrencia_dias_semana": [1, 3],
    }))
    assert r["ok"] and r["datos"]["recurrencia_freq"] == "semanal"


def test_crear_evento_regla_invalida():
    db = FakeDB()
    r = asyncio.run(registro.ejecutar(db, "crear_evento", {
        "titulo": "X", "inicia_en": _ANCLA, "recurrencia_freq": "cada_rato",
    }))
    assert r["ok"] is False and r["tipo"] == "validacion"


def test_crear_recurrente_fin_hasta_sin_fecha_es_error():
    r = asyncio.run(registro.ejecutar(FakeDB(), "crear_evento", {
        "titulo": "X", "inicia_en": _ANCLA, "recurrencia_freq": "diaria",
        "recurrencia_fin_tipo": "hasta",
    }))
    assert r["ok"] is False and r["tipo"] == "validacion"


# ── Consultar expande la recurrencia con el motor único ──────────────────────


def test_consultar_expande_ocurrencias():
    db = FakeDB({"eventos": [_serie_semanal()]})
    r = asyncio.run(registro.ejecutar(db, "consultar_eventos", {
        "desde": "2026-06-01", "hasta": "2026-06-07",
    }))
    assert r["ok"] and r["datos"]["total"] == 1
    ocs = r["datos"]["eventos"][0]["ocurrencias"]
    assert ocs == ["2026-06-01", "2026-06-03"]  # lunes y miércoles


# ── Editar: toda_serie vs solo_esta vs esta_y_futuras ────────────────────────


def test_editar_toda_serie():
    db = FakeDB({"eventos": [_serie_semanal()]})
    r = asyncio.run(registro.ejecutar(db, "editar_evento", {
        "evento_id": _EV, "titulo": "Gimnasio",
    }))
    assert r["ok"] and _eventos(db)[0]["titulo"] == "Gimnasio"
    assert len(_eventos(db)) == 1  # no partió nada


def test_editar_solo_esta_detacha_una_instancia():
    db = FakeDB({"eventos": [_serie_semanal()]})
    r = asyncio.run(registro.ejecutar(db, "editar_evento", {
        "evento_id": _EV, "titulo": "Gym (movido)",
        "alcance": "solo_esta", "ocurrencia_fecha": "2026-06-03",
    }))
    assert r["ok"]
    # La serie original ahora EXCLUYE el 3-jun.
    serie = next(e for e in _eventos(db) if e["id"] == _EV)
    assert "2026-06-03" in (serie.get("recurrencia_excepciones") or [])
    # Y nació un evento ÚNICO (sin recurrencia) para ese día con el cambio.
    nuevos = [e for e in _eventos(db) if e["id"] != _EV]
    assert len(nuevos) == 1
    assert nuevos[0]["titulo"] == "Gym (movido)"
    assert not nuevos[0].get("recurrencia_freq")
    assert nuevos[0]["inicia_en"].startswith("2026-06-03")


def test_editar_esta_y_futuras_parte_la_serie():
    db = FakeDB({"eventos": [_serie_semanal()]})
    r = asyncio.run(registro.ejecutar(db, "editar_evento", {
        "evento_id": _EV, "titulo": "Gym nuevo plan",
        "alcance": "esta_y_futuras", "ocurrencia_fecha": "2026-06-08",
    }))
    assert r["ok"]
    # La original se corta el día anterior (7-jun).
    orig = next(e for e in _eventos(db) if e["id"] == _EV)
    assert orig["recurrencia_fin_tipo"] == "hasta"
    assert orig["recurrencia_hasta"] == "2026-06-07"
    # Nació una serie NUEVA desde el 8-jun, mantiene la recurrencia.
    nuevos = [e for e in _eventos(db) if e["id"] != _EV]
    assert len(nuevos) == 1
    assert nuevos[0]["recurrencia_freq"] == "semanal"
    assert nuevos[0]["inicia_en"].startswith("2026-06-08")
    assert nuevos[0]["titulo"] == "Gym nuevo plan"


# ── Borrar: los tres alcances ────────────────────────────────────────────────


def test_borrar_toda_serie_es_soft_delete():
    db = FakeDB({"eventos": [_serie_semanal()]})
    r = asyncio.run(registro.ejecutar(db, "eliminar_evento", {"evento_id": _EV}))
    assert r["ok"] and _eventos(db)[0].get("eliminado_en")


def test_borrar_solo_esta_agrega_excepcion_sin_borrar():
    db = FakeDB({"eventos": [_serie_semanal()]})
    r = asyncio.run(registro.ejecutar(db, "eliminar_evento", {
        "evento_id": _EV, "alcance": "solo_esta", "ocurrencia_fecha": "2026-06-03",
    }))
    assert r["ok"]
    serie = _eventos(db)[0]
    assert serie.get("eliminado_en") is None  # la serie sigue viva
    assert "2026-06-03" in (serie.get("recurrencia_excepciones") or [])
    # El motor ya no la cuenta como ocurrencia.
    assert recurrencia.ocurre_en(serie, date(2026, 6, 3)) is False
    assert recurrencia.ocurre_en(serie, date(2026, 6, 1)) is True


def test_borrar_esta_y_futuras_trunca_la_serie():
    db = FakeDB({"eventos": [_serie_semanal()]})
    r = asyncio.run(registro.ejecutar(db, "eliminar_evento", {
        "evento_id": _EV, "alcance": "esta_y_futuras", "ocurrencia_fecha": "2026-06-08",
    }))
    assert r["ok"]
    serie = _eventos(db)[0]
    assert serie["recurrencia_fin_tipo"] == "hasta"
    assert serie["recurrencia_hasta"] == "2026-06-07"


# ── D4: las 3 rutas de creación van por el MISMO comando ─────────────────────


def test_d4_tres_rutas_de_creacion_un_comando():
    """Manual (router), OCR de sílabo (la app persiste tras extraer) e IA crean
    por `crear_evento`. Aquí: las tres rutas terminan en el mismo handler."""
    args = {"titulo": "Reunión", "inicia_en": "2026-06-10T15:00:00-05:00"}
    db_manual, db_ocr, db_ia = FakeDB(), FakeDB(), FakeDB()
    # Manual: lo que hace el router POST /eventos.
    r1 = asyncio.run(registro.ejecutar(db_manual, "crear_evento", dict(args), origen="ui"))
    # OCR de sílabo: la app, tras /extraer-eventos, persiste por el MISMO comando.
    r2 = asyncio.run(registro.ejecutar(db_ocr, "crear_evento", dict(args), origen="ocr"))
    # IA: la tool envuelve el mismo comando.
    r3 = asyncio.run(tools.ejecutar_tool(db_ia, "crear_evento", dict(args)))
    assert r1["ok"] and r2["ok"] and r3["ok"]
    assert _eventos(db_manual)[0]["titulo"] == _eventos(db_ocr)[0]["titulo"] == "Reunión"
    assert _eventos(db_ia)[0]["titulo"] == "Reunión"


def test_paridad_ui_ia_crear_evento():
    db_ui, db_ia = FakeDB(), FakeDB()
    args = {"titulo": "Charla", "inicia_en": "2026-06-12T10:00:00-05:00"}
    r_ui = asyncio.run(registro.ejecutar(db_ui, "crear_evento", dict(args), origen="ui"))
    r_ia = asyncio.run(tools.ejecutar_tool(db_ia, "crear_evento", dict(args)))
    assert r_ui["ok"] and r_ia["ok"]
    assert _eventos(db_ui)[0]["titulo"] == _eventos(db_ia)[0]["titulo"] == "Charla"


def test_ia_borrar_evento_pide_confirmacion():
    db = FakeDB({"eventos": [_serie_semanal()]})
    r = asyncio.run(tools.ejecutar_tool(db, "eliminar_evento", {"evento_id": _EV}))
    assert r["ok"] is False and r["tipo"] == "requiere_confirmacion"
    r2 = asyncio.run(tools.ejecutar_tool(
        db, "eliminar_evento", {"evento_id": _EV, "confirmado": True}))
    assert r2["ok"] and _eventos(db)[0].get("eliminado_en")


# ── Unificación: clases y eventos comparten el motor de recurrencia ──────────


def test_recurrencia_clases_y_eventos_un_solo_motor():
    """Un EVENTO semanal lunes+miércoles y unas SESIONES de clase lunes (0) +
    miércoles (2) coinciden en QUÉ días caen, resueltos por el MISMO módulo
    `comandos.recurrencia`. Una sola fuente de verdad para 'esto se repite'."""
    evento = _serie_semanal()  # ISO [1, 3]
    for d in range(1, 8):  # 2026-06-01 (lun) … 06-07 (dom)
        fecha = date(2026, 6, d)
        por_evento = recurrencia.ocurre_en(evento, fecha)
        por_clase = (recurrencia.sesion_ocurre_en(0, fecha)  # lunes
                     or recurrencia.sesion_ocurre_en(2, fecha))  # miércoles
        assert por_evento == por_clase, fecha
