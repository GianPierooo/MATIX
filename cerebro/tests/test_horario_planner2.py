"""Inteligencia del planificador (Prompt 2): buffer de TRANSICIÓN tras
compromisos fuera de casa (#1), NINGÚN proyecto activo sin acción siguiente
(#2) y el apartado de HUECOS libres con una sugerencia dosificada que cabe (#3).

La lógica núcleo es PURA y se testea sin BD; un par de pruebas de integración
con FakeDB verifican el cableado (la clase genera transición; cada proyecto
queda con acción)."""
from __future__ import annotations

import asyncio
from datetime import date, datetime, timezone

from app.matix import horario as h

DESPERTAR = 7 * 60   # 420
DORMIR = 23 * 60     # 1380


# ── #1 · Transición tras compromisos fuera de casa ───────────────────────────

def test_bloques_transicion_solo_tras_fuera_de_casa():
    fijos = [
        {"ini_min": 480, "fin_min": 600, "fuera_casa": True, "titulo": "Clase"},
        {"ini_min": 700, "fin_min": 760, "titulo": "Algo en casa"},  # sin fuera_casa
    ]
    t = h.bloques_transicion(fijos, transicion_default_min=60)
    assert t == [{"ini_min": 600, "fin_min": 660, "tipo": "transicion",
                  "titulo": "Transición"}]


def test_bloques_transicion_respeta_override_y_cero():
    fijos = [
        {"ini_min": 480, "fin_min": 600, "fuera_casa": True, "transicion_min": 30,
         "titulo": "Gym"},
        {"ini_min": 700, "fin_min": 760, "fuera_casa": True, "transicion_min": 0,
         "titulo": "Acá nomás"},  # override 0 → sin transición
    ]
    t = h.bloques_transicion(fijos, transicion_default_min=60)
    assert len(t) == 1                       # el de override 0 no genera nada
    assert t[0]["ini_min"] == 600 and t[0]["fin_min"] == 630  # usó el override (30)


def test_transicion_bloquea_trabajo_de_casa_en_las_ventanas():
    # Clase 8:00–10:00 (fuera de casa) + 1h de transición → 10:00–11:00 NO es
    # tiempo para trabajo de casa. Con buffer 10 todo se funde 7:50–11:10.
    fijos = [{"ini_min": 480, "fin_min": 600, "tipo": "clase", "titulo": "Cálculo",
              "fuera_casa": True}]
    fijos += h.bloques_transicion(fijos, transicion_default_min=60)
    v = h.ventanas_libres(fijos, despertar_min=DESPERTAR, dormir_min=DORMIR,
                          buffer_min=10)
    # Hay ventana antes de clase y otra recién a las 11:10; NINGUNA toca 10–11.
    assert any(w["ini"] == 420 and w["fin"] == 470 for w in v)   # 7:00–7:50
    assert any(w["ini"] == 670 for w in v)                       # 11:10 en adelante
    assert not any(w["ini"] < 660 and w["fin"] > 600 for w in v)  # nada en 10:00–11:00


# ── #2 · Ningún proyecto activo sin acción siguiente ─────────────────────────

def test_accion_siguiente_usa_el_nodo_del_arbol():
    p = {"id": "p1", "nombre": "OneXotic", "prioridad": 1}
    cands = [{"id": "n1", "titulo": "Diseñar la landing"}]
    it = h.accion_siguiente_proyecto(p, cands, dur_trabajo_min=90)
    assert it["titulo"] == "Diseñar la landing"
    assert it["nodo_id"] == "n1"
    assert it["tipo"] == "trabajo" and it["proyecto_id"] == "p1"
    assert it["prioridad"] == 1 and it["auto_siguiente"] is True
    assert "auto_planificacion" not in it            # vino del árbol, no es placeholder


def test_accion_siguiente_sintetiza_planificacion_sin_arbol():
    p = {"id": "p2", "nombre": "Shadow Games", "prioridad": 2}
    it = h.accion_siguiente_proyecto(p, [], dur_trabajo_min=90)
    assert it["titulo"] == "Definir el siguiente paso de Shadow Games"
    assert it["auto_planificacion"] is True
    assert it.get("nodo_id") is None                 # no hay nodo: es planificación
    assert it["tipo"] == "trabajo" and it["proyecto_id"] == "p2"


# ── #3 · Apartado de huecos libres + sugerencia dosificada que cabe ──────────

def test_etiqueta_duracion_legible():
    assert h.etiqueta_duracion(45) == "45 min"
    assert h.etiqueta_duracion(60) == "1 h"
    assert h.etiqueta_duracion(90) == "1 h 30 min"
    assert h.etiqueta_duracion(0) == "0 min"


def test_huecos_libres_son_lo_que_queda_tras_colocar_todo():
    bloques = [{"ini_min": 420, "fin_min": 540},   # 7–9 ocupado
               {"ini_min": 600, "fin_min": 660}]   # 10–11 ocupado
    g = h.huecos_libres(bloques, inicio_min=420, fin_min=1320)  # 7:00–22:00
    assert {"ini": 540, "fin": 600, "dur": 60} in g             # 9–10 libre
    assert g[-1] == {"ini": 660, "fin": 1320, "dur": 660}       # 11–22 libre


def test_huecos_con_sugerencia_una_que_cabe_por_hueco_sin_repetir():
    huecos = [{"ini": 540, "fin": 580, "dur": 40},      # 40 min
              {"ini": 660, "fin": 1320, "dur": 660}]    # 11 h
    pool = [
        {"titulo": "OneXotic: landing", "tipo": "trabajo", "dur_min": 90,
         "proyecto": "OneXotic"},
        {"titulo": "Práctica: Inglés", "tipo": "skill", "dur_min": 30,
         "skill": "Inglés"},
    ]
    out = h.huecos_con_sugerencia(huecos, pool)
    # Hueco de 40 min: el trabajo de 90 NO cabe → ofrece la skill de 30.
    assert out[0]["sugerencia"]["skill"] == "Inglés"
    assert out[0]["etiqueta"] == "40 min"
    # Hueco grande: ofrece el trabajo (la skill ya se usó: una cosa por hueco).
    assert out[1]["sugerencia"]["titulo"] == "OneXotic: landing"


def test_huecos_sin_sugerencia_si_nada_cabe():
    out = h.huecos_con_sugerencia(
        [{"ini": 540, "fin": 560, "dur": 20}],
        [{"titulo": "X", "tipo": "trabajo", "dur_min": 90}],
    )
    assert out[0]["sugerencia"] is None      # honesto: hueco libre, nada que entre


# ── Integración (FakeDB) ─────────────────────────────────────────────────────

class FakeDB:
    """Postgrest mínimo en memoria: list con filtro por `filters` (ignora
    raw_filters/order, suficiente para estas pruebas)."""

    def __init__(self, tablas):
        self.tablas = tablas

    async def list(self, tabla, *, filters=None, raw_filters=None, order=None, limit=None):
        filas = list(self.tablas.get(tabla, []))
        if filters:
            for k, v in filters.items():
                filas = [f for f in filas if f.get(k) == v]
        if limit is not None:
            filas = filas[:limit]
        return filas

    async def insert(self, tabla, row):
        fila = {"id": f"{tabla}-x", **row}
        self.tablas.setdefault(tabla, []).append(fila)
        return fila

    async def update(self, tabla, id_, payload):
        return {"id": id_, **payload}


def test_clase_de_hoy_reserva_transicion_y_corre_el_trabajo_de_casa():
    ahora = datetime(2026, 6, 8, 17, 0, tzinfo=timezone.utc)  # 12:00 Lima
    fecha = ahora.astimezone(h.LIMA).date()
    db = FakeDB({
        "config_horario": [],          # defaults: transicion 60, ancla Calistenia
        "despertar_dia": [],
        "proyectos": [{"id": "p1", "nombre": "OneXotic", "estado": "activo"}],
        "set_diario_items": [{
            "id": "s1", "fecha": fecha.isoformat(), "proyecto_id": "p1",
            "titulo": "OneXotic: sprint", "estado": "propuesto", "orden": 0,
        }],
        "sesiones_clase": [{
            "curso_id": "c1", "dia_semana": fecha.weekday(),
            "hora_inicio": "08:00", "hora_fin": "10:00",
        }],
        "cursos": [{"id": "c1", "nombre": "Cálculo"}],
        "eventos": [], "tareas": [], "arbol_nodos": [],
    })
    plan = asyncio.run(h.plan_de_hoy_data(db, ahora=ahora))

    trans = [b for b in plan["bloques"] if b["tipo"] == "transicion"]
    assert len(trans) == 1
    assert trans[0]["inicio"] == "10:00" and trans[0]["fin"] == "11:00"
    assert trans[0]["tentativo"] is False           # la transición es fija, no se mueve

    # El trabajo de casa (tentativo) NO se coloca durante/antes de la transición.
    tent = [b for b in plan["bloques"] if b.get("tentativo") and b["tipo"] == "trabajo"]
    assert tent, "el trabajo de casa debería colocarse en alguna ventana"
    assert all(b["inicio"] >= "11:00" for b in tent)


def test_ningun_proyecto_activo_queda_sin_accion_siguiente():
    fecha = date(2026, 6, 8)
    db = FakeDB({
        # 3 proyectos de trabajo activos; solo p1 está en el set de hoy.
        "proyectos": [
            {"id": "p1", "nombre": "OneXotic", "estado": "activo"},
            {"id": "p2", "nombre": "Matix 1.0", "estado": "activo"},
            {"id": "p3", "nombre": "Shadow Games", "estado": "activo"},
        ],
        "set_diario_items": [{
            "id": "s1", "fecha": fecha.isoformat(), "proyecto_id": "p1",
            "titulo": "OneXotic: sprint", "estado": "propuesto", "orden": 0,
        }],
        "tareas": [],
        # p2 tiene árbol (un nodo fino abierto); p3 no tiene árbol.
        "arbol_nodos": [
            {"id": "f2", "proyecto_id": "p2", "parent_id": None, "orden": 0,
             "granularidad": "grueso", "estado": "pendiente"},
            {"id": "n2", "proyecto_id": "p2", "parent_id": "f2", "orden": 0,
             "granularidad": "fino", "estado": "pendiente"},
        ],
    })
    items = asyncio.run(h._items_a_colocar(
        db, fecha=fecha, cfg=h._CFG_DEFAULT, solo_pendientes=False,
        titulos_fijos=set(),
    ))
    trabajo_por_proy = {i.get("proyecto_id") for i in items if i.get("tipo") == "trabajo"}
    assert {"p1", "p2", "p3"} <= trabajo_por_proy   # NINGUNO queda sin acción

    # p2 derivó su siguiente paso del árbol (con nodo real).
    p2i = next(i for i in items if i.get("proyecto_id") == "p2" and i.get("auto_siguiente"))
    assert p2i["nodo_id"] == "n2"
    assert "auto_planificacion" not in p2i

    # p3 (sin árbol) recibió la acción de planificación sintetizada.
    p3i = next(i for i in items if i.get("proyecto_id") == "p3")
    assert p3i.get("auto_planificacion") is True
    assert p3i["titulo"] == "Definir el siguiente paso de Shadow Games"
