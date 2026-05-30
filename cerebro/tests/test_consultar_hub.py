"""Tests de "pregúntale a tu hub" (consultas de Matix sobre sus datos).

Dos capas:
- Filtros puros (`filtrar_tareas`, `eventos_en_rango`, `filtrar_proyectos`):
  rápidos, sin BD. Verifican que las tools filtran bien.
- Pregunta combinada: con el LLM mockeado, una pregunta de "esta semana"
  dispara `consultar_eventos` + `consultar_tareas` (el loop ejecuta las
  dos y sintetiza).
"""
from __future__ import annotations

from datetime import date, datetime, timezone

import pytest

from app.matix import chat as chat_mod
from app.matix.tools import (
    eventos_en_rango,
    filtrar_proyectos,
    filtrar_tareas,
)

# ─── Filtros puros ───────────────────────────────────────────────────


def _tarea(tid, *, comp=False, proyecto=None, curso=None, vence=None, borrada=False):
    return {
        "id": tid,
        "titulo": tid,
        "completada": comp,
        "proyecto_id": proyecto,
        "curso_id": curso,
        "vence_en": vence,
        "eliminado_en": "2026-01-01T00:00:00+00:00" if borrada else None,
    }


def test_filtrar_tareas_por_proyecto_y_estado() -> None:
    tareas = [
        _tarea("a", proyecto="p1"),
        _tarea("b", comp=True, proyecto="p1"),
        _tarea("c", proyecto="p2"),
        _tarea("d", proyecto="p1", borrada=True),
    ]
    pend_p1 = filtrar_tareas(tareas, proyecto_id="p1", estado="pendiente")
    assert [t["id"] for t in pend_p1] == ["a"]  # b completada, d papelera
    comp = filtrar_tareas(tareas, estado="completada")
    assert [t["id"] for t in comp] == ["b"]


def test_filtrar_tareas_por_rango_excluye_sin_fecha() -> None:
    tareas = [
        _tarea("en", vence="2026-06-10T15:00:00+00:00"),
        _tarea("fuera", vence="2026-07-20T15:00:00+00:00"),
        _tarea("sinfecha", vence=None),
    ]
    r = filtrar_tareas(
        tareas,
        estado="pendiente",
        vence_desde=date(2026, 6, 8),
        vence_hasta=date(2026, 6, 14),
    )
    assert [t["id"] for t in r] == ["en"]


def test_eventos_en_rango_incluye_recurrentes() -> None:
    eventos = [
        {"id": "e1", "inicia_en": "2026-06-10T15:00:00+00:00"},
        {
            "id": "e2",
            "inicia_en": "2026-05-01T15:00:00+00:00",
            "recurrencia_freq": "semanal",
        },
        {"id": "e3", "inicia_en": "2026-01-01T15:00:00+00:00"},
    ]
    r = eventos_en_rango(eventos, date(2026, 6, 8), date(2026, 6, 14))
    ids = {e["id"] for e in r}
    assert ids == {"e1", "e2"}  # e1 cae en rango; e2 recurrente; e3 fuera
    assert next(e for e in r if e["id"] == "e2").get("_recurrente") is True


def test_filtrar_proyectos_en_riesgo() -> None:
    ahora = datetime(2026, 6, 10, tzinfo=timezone.utc)
    proyectos = [
        {"id": "p1", "nombre": "Tesis", "estado": "activo",
         "ultima_actividad_en": "2026-06-01T00:00:00+00:00"},  # 9 días
        {"id": "p2", "nombre": "Web", "estado": "activo",
         "ultima_actividad_en": "2026-06-10T00:00:00+00:00"},  # hoy
        {"id": "p3", "nombre": "Viejo", "estado": "aparcado",
         "ultima_actividad_en": "2026-01-01T00:00:00+00:00"},
    ]
    riesgo = filtrar_proyectos(proyectos, en_riesgo=True, ahora=ahora)
    assert [p["nombre"] for p in riesgo] == ["Tesis"]
    activos = filtrar_proyectos(proyectos, estado="activo", ahora=ahora)
    assert {p["nombre"] for p in activos} == {"Tesis", "Web"}


# ─── Pregunta combinada (loop de tools) ──────────────────────────────


async def test_pregunta_combinada_usa_varias_tools(
    _fresh_db, monkeypatch: pytest.MonkeyPatch
) -> None:
    """«¿qué se me viene esta semana?» → eventos + tareas, y sintetiza."""
    respuestas = [
        {
            "tipo": "tool_calls",
            "raw": {"role": "assistant", "content": None},
            "tool_calls": [
                {
                    "id": "c1",
                    "nombre": "consultar_eventos",
                    "args": {"desde": "2026-06-08", "hasta": "2026-06-14"},
                },
                {
                    "id": "c2",
                    "nombre": "consultar_tareas",
                    "args": {
                        "vence_desde": "2026-06-08",
                        "vence_hasta": "2026-06-14",
                    },
                },
            ],
        },
        {"tipo": "texto", "contenido": "Esta semana tienes un par de cosas."},
    ]
    it = iter(respuestas)

    async def fake_responder(mensajes, tools, tool_choice=None):  # noqa: ANN001, ARG001
        return next(it)

    monkeypatch.setattr(chat_mod.llm, "responder_con_tools", fake_responder)

    res = await chat_mod.conversar(
        _fresh_db, historial=[], mensaje="¿qué se me viene esta semana?"
    )
    assert "consultar_eventos" in res["tools_usadas"]
    assert "consultar_tareas" in res["tools_usadas"]
    assert res["respuesta"].startswith("Esta semana")
    # Son solo lectura: no marcan tablas para invalidar.
    assert res["tablas_cambiadas"] == []
