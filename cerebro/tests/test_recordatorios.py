"""Tests de la selección de recordatorios del scheduler (Push Capa 2).

`seleccionar` es PURO (sin BD ni FCM): dado los candidatos crudos, el set
de claves ya enviadas y `ahora`, devuelve qué recordatorios mandar.
Cubre: due dentro de la ventana, dedupe, lookback (catch-up) y futuro.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from app.matix.recordatorios import seleccionar

AHORA = datetime(2026, 5, 30, 17, 0, 0, tzinfo=timezone.utc)


def _z(d: datetime) -> str:
    return d.strftime("%Y-%m-%dT%H:%M:%SZ")


def _tarea(tid: str, recordar_en: datetime, titulo: str = "Tarea"):
    return {
        "id": tid,
        "titulo": titulo,
        "recordar_en": _z(recordar_en),
        "completada": False,
    }


def _evento(eid: str, recordar_en: datetime, inicia_en: datetime, titulo="Evento"):
    return {
        "id": eid,
        "titulo": titulo,
        "recordar_en": _z(recordar_en),
        "inicia_en": _z(inicia_en),
        "ubicacion": None,
    }


def test_due_dentro_de_la_ventana():
    tareas = [_tarea("11111111-1111-1111-1111-111111111111", AHORA, "Pagar luz")]
    eventos = [
        _evento(
            "22222222-2222-2222-2222-222222222222",
            AHORA,
            AHORA + timedelta(minutes=10),
            "Reunión",
        )
    ]
    out = seleccionar(tareas=tareas, eventos=eventos, enviados=set(), ahora=AHORA)
    assert {r.tipo for r in out} == {"tarea", "evento"}
    ev = next(r for r in out if r.tipo == "evento")
    assert ev.payload == "evento:22222222-2222-2222-2222-222222222222"
    # Hora en Lima (UTC-5): 17:10 UTC → 12:10.
    assert "12:10" in ev.cuerpo


def test_dedupe_no_reenvia_lo_ya_enviado():
    tareas = [_tarea("11111111-1111-1111-1111-111111111111", AHORA)]
    primera = seleccionar(tareas=tareas, eventos=[], enviados=set(), ahora=AHORA)
    assert len(primera) == 1
    enviados = {primera[0].clave}
    segunda = seleccionar(
        tareas=tareas, eventos=[], enviados=enviados, ahora=AHORA
    )
    assert segunda == []


def test_catch_up_dentro_del_lookback_pero_no_los_viejos():
    # Hace 5 min (dentro del lookback de 10) → se manda (catch-up).
    reciente = _tarea("a" * 8 + "-0000-0000-0000-000000000000", AHORA - timedelta(minutes=5))
    # Hace 30 min (fuera del lookback) → NO se manda (no spamear).
    viejo = _tarea("b" * 8 + "-0000-0000-0000-000000000000", AHORA - timedelta(minutes=30))
    out = seleccionar(
        tareas=[reciente, viejo], eventos=[], enviados=set(), ahora=AHORA
    )
    assert len(out) == 1
    assert out[0].recordar_en == AHORA - timedelta(minutes=5)


def test_futuro_no_se_manda():
    futuro = _tarea("c" * 8 + "-0000-0000-0000-000000000000", AHORA + timedelta(minutes=5))
    out = seleccionar(tareas=[futuro], eventos=[], enviados=set(), ahora=AHORA)
    assert out == []
