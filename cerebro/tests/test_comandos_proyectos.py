"""Capa de comandos (2.0 · Fase 4) — Proyectos.

Verifica: CRUD + cambios de estado por comando, la acción siguiente G9 (DEFINIR/
CAMBIAR, no solo marcar), la consolidación de completar avance por cualquier
camino (D5 resto), la paridad UI↔IA, y que el motor de evolución sigue
alimentado (estados de nodos + ultima_actividad_en). FakeDB en memoria.
"""
from __future__ import annotations

import asyncio

from app.comandos import registro
from app.matix import avance as avance_mod
from app.matix import horario, tools

_P = "66666666-6666-6666-6666-666666666666"
_P2 = "77777777-7777-7777-7777-777777777777"
_T = "88888888-8888-8888-8888-888888888888"
_NODO = "99999999-9999-9999-9999-999999999999"


class FakeDB:
    def __init__(self, tablas: dict[str, list[dict]] | None = None) -> None:
        self.tablas: dict[str, list[dict]] = tablas or {}
        self.updates: list[tuple[str, str, dict]] = []
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
        self.updates.append((tabla, str(id_), payload))
        for f in self.tablas.get(tabla, []):
            if str(f.get("id")) == str(id_):
                f.update(payload)
                return f
        return None

    async def delete(self, tabla, id_):
        antes = len(self.tablas.get(tabla, []))
        self.tablas[tabla] = [f for f in self.tablas.get(tabla, []) if str(f.get("id")) != str(id_)]
        return len(self.tablas.get(tabla, [])) < antes


def _proys(db: FakeDB) -> list[dict]:
    return db.tablas.get("proyectos", [])


# ── El registro ──────────────────────────────────────────────────────────────


def test_registro_tiene_comandos_proyectos():
    for n in ("crear_proyecto", "editar_proyecto", "aparcar_proyecto",
              "terminar_proyecto", "reactivar_proyecto", "eliminar_proyecto",
              "definir_accion_siguiente", "marcar_accion_siguiente_hecha",
              "completar_avance_proyecto", "consultar_proyectos"):
        assert registro.existe(n), n
    assert registro.get("crear_proyecto").riesgo.value == "consecuente"
    assert registro.get("consultar_proyectos").riesgo.value == "segura"


# ── Crear + tope de 3 ────────────────────────────────────────────────────────


def test_crear_proyecto_inserta():
    db = FakeDB()
    r = asyncio.run(registro.ejecutar(db, "crear_proyecto", {"nombre": "Tesis"}))
    assert r["ok"] and r["datos"]["nombre"] == "Tesis"
    assert _proys(db)[0]["estado"] == "activo"
    assert _proys(db)[0].get("ultima_actividad_en")


def test_crear_proyecto_respeta_tope_de_3():
    db = FakeDB({"proyectos": [
        {"id": "a", "nombre": "A", "estado": "activo", "es_skill": False},
        {"id": "b", "nombre": "B", "estado": "activo", "es_skill": False},
        {"id": "c", "nombre": "C", "estado": "activo", "es_skill": False},
    ]})
    r = asyncio.run(registro.ejecutar(db, "crear_proyecto", {"nombre": "D"}))
    assert r["ok"] is False and r["tipo"] == "tope_proyectos"
    # Una skill NO consume el tope: se puede crear igual.
    r2 = asyncio.run(registro.ejecutar(db, "crear_proyecto", {"nombre": "Inglés", "es_skill": True}))
    assert r2["ok"]


def test_crear_proyecto_aparcado_no_cuenta_tope():
    db = FakeDB({"proyectos": [
        {"id": "a", "nombre": "A", "estado": "activo", "es_skill": False},
        {"id": "b", "nombre": "B", "estado": "activo", "es_skill": False},
        {"id": "c", "nombre": "C", "estado": "activo", "es_skill": False},
    ]})
    r = asyncio.run(registro.ejecutar(db, "crear_proyecto", {"nombre": "D", "estado": "aparcado"}))
    assert r["ok"]


# ── Estado: aparcar / terminar / reactivar ───────────────────────────────────


def test_aparcar_fija_inactivo_desde():
    db = FakeDB({"proyectos": [{"id": _P, "nombre": "X", "estado": "activo"}]})
    r = asyncio.run(registro.ejecutar(db, "aparcar_proyecto", {"proyecto_id": _P}))
    assert r["ok"] and _proys(db)[0]["estado"] == "aparcado"
    assert _proys(db)[0]["inactivo_desde"]


def test_reactivar_respeta_tope():
    db = FakeDB({"proyectos": [
        {"id": "a", "nombre": "A", "estado": "activo", "es_skill": False},
        {"id": "b", "nombre": "B", "estado": "activo", "es_skill": False},
        {"id": "c", "nombre": "C", "estado": "activo", "es_skill": False},
        {"id": _P, "nombre": "Z", "estado": "aparcado", "es_skill": False},
    ]})
    r = asyncio.run(registro.ejecutar(db, "reactivar_proyecto", {"proyecto_id": _P}))
    assert r["ok"] is False and r["tipo"] == "tope_proyectos"


# ── Acción siguiente (G9): definir / cambiar ─────────────────────────────────


def test_definir_accion_siguiente_define_y_vincula():
    db = FakeDB({
        "proyectos": [{"id": _P, "nombre": "Tesis", "estado": "activo"}],
        "tareas": [{"id": _T, "titulo": "Escribir intro", "proyecto_id": None}],
    })
    r = asyncio.run(registro.ejecutar(db, "definir_accion_siguiente",
                                      {"proyecto_id": _P, "tarea_id": _T}))
    assert r["ok"]
    assert _proys(db)[0]["tarea_siguiente_id"] == _T
    # La tarea libre quedó vinculada al proyecto.
    assert db.tablas["tareas"][0]["proyecto_id"] == _P


def test_definir_accion_siguiente_rechaza_tarea_de_otro_proyecto():
    db = FakeDB({
        "proyectos": [{"id": _P, "nombre": "Tesis", "estado": "activo"}],
        "tareas": [{"id": _T, "titulo": "X", "proyecto_id": _P2}],
    })
    r = asyncio.run(registro.ejecutar(db, "definir_accion_siguiente",
                                      {"proyecto_id": _P, "tarea_id": _T}))
    assert r["ok"] is False and r["tipo"] == "conflicto"


def test_cambiar_accion_siguiente():
    db = FakeDB({
        "proyectos": [{"id": _P, "nombre": "Tesis", "estado": "activo", "tarea_siguiente_id": _T}],
        "tareas": [
            {"id": _T, "titulo": "vieja", "proyecto_id": _P},
            {"id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "titulo": "nueva", "proyecto_id": _P},
        ],
    })
    r = asyncio.run(registro.ejecutar(db, "definir_accion_siguiente",
                                      {"proyecto_id": _P, "tarea_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}))
    assert r["ok"] and _proys(db)[0]["tarea_siguiente_id"] == "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"


def test_quitar_accion_siguiente_con_null():
    db = FakeDB({"proyectos": [
        {"id": _P, "nombre": "Tesis", "estado": "activo", "tarea_siguiente_id": _T}]})
    r = asyncio.run(registro.ejecutar(db, "definir_accion_siguiente",
                                      {"proyecto_id": _P, "tarea_id": None}))
    assert r["ok"] and _proys(db)[0]["tarea_siguiente_id"] is None


def test_marcar_accion_siguiente_hecha_completa_y_limpia():
    db = FakeDB({
        "proyectos": [{"id": _P, "nombre": "Tesis", "estado": "activo", "tarea_siguiente_id": _T}],
        "tareas": [{"id": _T, "titulo": "Escribir", "completada": False, "proyecto_id": _P}],
    })
    r = asyncio.run(registro.ejecutar(db, "marcar_accion_siguiente_hecha", {"proyecto_id": _P}))
    assert r["ok"] and r["datos"]["tarea_completada"] == "Escribir"
    # La tarea se completó (por el comando canónico) y se limpió el puntero.
    assert db.tablas["tareas"][0]["completada"] is True
    assert _proys(db)[0]["tarea_siguiente_id"] is None


# ── D5 resto: completar avance por cualquier camino deja el mismo % ──────────


def _db_con_arbol():
    """Proyecto con 2 nodos (uno ya hecho), para medir el %."""
    return FakeDB({
        "proyectos": [{"id": _P, "nombre": "Tesis", "estado": "activo"}],
        "arbol_nodos": [
            {"id": _NODO, "proyecto_id": _P, "titulo": "Paso A", "estado": "pendiente", "tamano": "medio"},
            {"id": "nodo-b", "proyecto_id": _P, "titulo": "Paso B", "estado": "hecho", "tamano": "medio"},
        ],
    })


def test_completar_avance_por_comando_marca_nodo_y_refresca_actividad():
    db = _db_con_arbol()
    r = asyncio.run(registro.ejecutar(db, "completar_avance_proyecto", {"nodo_id": _NODO}))
    assert r["ok"]
    nodo = next(n for n in db.tablas["arbol_nodos"] if n["id"] == _NODO)
    assert nodo["estado"] == "hecho"
    # El % subió (ambos nodos hechos) y el motor de evolución quedó alimentado:
    # la actividad del proyecto se refrescó.
    assert r["datos"]["avance"] == 100
    assert _proys(db)[0].get("ultima_actividad_en")


def test_d5_avance_por_comando_y_por_bloque_mismo_estado():
    # 1) Camino del comando directo (IA/UI).
    db_cmd = _db_con_arbol()
    asyncio.run(registro.ejecutar(db_cmd, "completar_avance_proyecto", {"nodo_id": _NODO}))
    # 2) Camino del bloque agendado (Tu día) — ahora enruta al MISMO comando.
    db_bloque = _db_con_arbol()
    asyncio.run(horario.completar_bloque(db_bloque, nodo_id=_NODO))
    for db in (db_cmd, db_bloque):
        nodo = next(n for n in db.tablas["arbol_nodos"] if n["id"] == _NODO)
        assert nodo["estado"] == "hecho"
        assert avance_mod.porcentaje(db.tablas["arbol_nodos"]) == 100


# ── Paridad UI ↔ IA ──────────────────────────────────────────────────────────


def test_ui_y_ia_crean_proyecto_por_el_mismo_comando():
    db_ui, db_ia = FakeDB(), FakeDB()
    r_ui = asyncio.run(registro.ejecutar(db_ui, "crear_proyecto", {"nombre": "App"}, origen="ui"))
    r_ia = asyncio.run(tools.ejecutar_tool(db_ia, "crear_proyecto", {"nombre": "App"}))
    assert r_ui["ok"] and r_ia["ok"]
    assert _proys(db_ui)[0]["nombre"] == _proys(db_ia)[0]["nombre"] == "App"
    assert r_ia["datos"]["nombre"] == "App"


def test_ia_definir_accion_siguiente_via_tool():
    db = FakeDB({
        "proyectos": [{"id": _P, "nombre": "Tesis", "estado": "activo"}],
        "tareas": [{"id": _T, "titulo": "X", "proyecto_id": None}],
    })
    r = asyncio.run(tools.ejecutar_tool(db, "definir_accion_siguiente",
                                        {"proyecto_id": _P, "tarea_id": _T}))
    assert r["ok"] and _proys(db)[0]["tarea_siguiente_id"] == _T


def test_ia_eliminar_proyecto_pide_confirmacion():
    db = FakeDB({"proyectos": [{"id": _P, "nombre": "X", "estado": "activo"}]})
    r = asyncio.run(tools.ejecutar_tool(db, "eliminar_proyecto", {"proyecto_id": _P}))
    assert r["ok"] is False and r["tipo"] == "requiere_confirmacion"
    r2 = asyncio.run(tools.ejecutar_tool(db, "eliminar_proyecto", {"proyecto_id": _P, "confirmado": True}))
    assert r2["ok"] and _proys(db) == []


# ── Consultar ────────────────────────────────────────────────────────────────


def test_consultar_proyectos_filtra_por_estado():
    db = FakeDB({"proyectos": [
        {"id": "a", "nombre": "A", "estado": "activo"},
        {"id": "b", "nombre": "B", "estado": "aparcado"},
    ]})
    r = asyncio.run(registro.ejecutar(db, "consultar_proyectos", {"estado": "activo"}))
    assert r["ok"] and r["datos"]["total"] == 1
    assert r["datos"]["proyectos"][0]["nombre"] == "A"


# ── Post-revisión: marcar acción siguiente propaga el error de completar ─────


def test_marcar_accion_siguiente_propaga_error_de_completar():
    """Si completar_tarea falla (p. ej. id no-UUID), NO se limpia el puntero ni
    se reporta éxito falso: el error se propaga."""
    db = FakeDB({
        "proyectos": [{"id": _P, "nombre": "Tesis", "estado": "activo", "tarea_siguiente_id": "bad-no-uuid"}],
        "tareas": [{"id": "bad-no-uuid", "titulo": "X", "completada": False, "proyecto_id": _P}],
    })
    r = asyncio.run(registro.ejecutar(db, "marcar_accion_siguiente_hecha", {"proyecto_id": _P}))
    assert r["ok"] is False  # propagó el error de completar_tarea (id inválido)
    # El puntero NO se limpió (no fingimos éxito).
    assert _proys(db)[0]["tarea_siguiente_id"] == "bad-no-uuid"
