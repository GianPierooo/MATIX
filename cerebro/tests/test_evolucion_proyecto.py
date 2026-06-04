"""Lógica pura del motor de evolución: revisión holística sin duplicar,
generación progresiva, detección de estancamiento y adaptación al ritmo. Sin BD.
"""
from __future__ import annotations

from datetime import datetime, timezone

from app.matix import evolucion_proyecto as ev


def _n(id, parent, estado="pendiente", orden=0, gran="fino"):
    return {"id": id, "parent_id": parent, "estado": estado, "orden": orden,
            "granularidad": gran, "titulo": id}


def test_filtrar_duplicados_quita_lo_existente_y_repetido():
    existentes = ["Leer 3 papers", "Redactar intro"]
    candidatas = ["leer 3 papers", "Analizar datos", "Analizar datos", "Redactar intro!"]
    out = ev.filtrar_duplicados(candidatas, existentes)
    # "leer 3 papers" y "Redactar intro!" ya existen; "Analizar datos" una sola vez
    assert out == ["Analizar datos"]


def test_fase_a_elaborar_devuelve_la_gruesa_que_toca():
    nodos = [
        _n("f1", None, "hecho", 0, gran="grueso"),       # fase 1 terminada
        _n("f2", None, "pendiente", 1, gran="grueso"),   # fase 2: gruesa, toca
        _n("f3", None, "pendiente", 2, gran="grueso"),
    ]
    fase = ev.fase_a_elaborar(nodos)
    assert fase is not None and fase["id"] == "f2"


def test_fase_a_elaborar_none_si_la_actual_es_fina_en_curso():
    nodos = [
        _n("f1", None, "pendiente", 0, gran="fino"),
        _n("a", "f1", "pendiente", 0),  # f1 tiene hijos → fina, en curso
        _n("f2", None, "pendiente", 1, gran="grueso"),
    ]
    assert ev.fase_a_elaborar(nodos) is None  # no adelantar fases lejanas


def test_estancado_por_dias_sin_actividad():
    ahora = datetime(2026, 6, 10, tzinfo=timezone.utc)
    assert ev.estancado("2026-06-09T12:00:00Z", ahora=ahora)["estancado"] is False
    r = ev.estancado("2026-06-01T12:00:00Z", ahora=ahora)
    assert r["estancado"] is True and r["dias"] >= 5


def test_evaluar_ritmo_adelantado_al_dia_atrasado():
    # 60% hecho cuando se esperaba ~25% → adelantado.
    assert ev.evaluar_ritmo(60, 25, 100)["ritmo"] == "adelantado"
    # 10% cuando se esperaba ~50% → atrasado, re-prioriza (no apila).
    atr = ev.evaluar_ritmo(10, 50, 100)
    assert atr["ritmo"] == "atrasado"
    assert "apil" in atr["recomendacion"].lower() or "prioriza" in atr["recomendacion"].lower()
    # ~al día.
    assert ev.evaluar_ritmo(48, 50, 100)["ritmo"] == "al_dia"


def test_copys_son_sanos():
    _, c = ev.texto_estancamiento("OnExotic", 7)
    assert "OnExotic" in c and "culpa" in c.lower()
    _, h = ev.texto_hito("Tesis", "Marco teórico")
    assert "Marco teórico" in h


def test_linea_checkin_honesta():
    # % + qué sigue.
    l = ev.linea_checkin_proyecto(nombre="Matix", pct=60, estancado_dias=0, siguiente="Cerrar X")
    assert "Matix" in l and "60%" in l and "Cerrar X" in l
    # Sin plan.
    assert "sin plan" in ev.linea_checkin_proyecto(nombre="Peyo", pct=None, estancado_dias=0, siguiente=None)
    # Trabado se dice honesto.
    assert "trabado 6d" in ev.linea_checkin_proyecto(nombre="Shadow", pct=20, estancado_dias=6, siguiente=None)


def test_texto_checkin_resumen_vs_generico():
    _, generico = ev.texto_checkin()
    assert "Revisemos" in generico
    _, resumen = ev.texto_checkin(["Matix (60%)", "Shadow (20%, trabado 6d)"])
    assert "Matix (60%)" in resumen and "Shadow" in resumen


def test_umbrales_cruzados():
    assert ev.umbrales_cruzados(None) == []
    assert ev.umbrales_cruzados(0) == []
    assert ev.umbrales_cruzados(30) == [25]
    assert ev.umbrales_cruzados(60) == [25, 50]
    assert ev.umbrales_cruzados(100) == [25, 50, 75, 100]


def test_texto_hito_pct():
    _, c50 = ev.texto_hito_pct("Inglés", 50)
    assert "50%" in c50
    t100, c100 = ev.texto_hito_pct("Peyo", 100)
    assert "100%" in c100 and ("cerr" in c100.lower() or "termin" in c100.lower())


def test_sugerir_reescopeo():
    assert ev.sugerir_reescopeo(None) is None
    s = ev.sugerir_reescopeo("Montar la pasarela de pago")
    assert "Montar la pasarela de pago" in s and "10-15" in s
