"""Tests de la lógica pura de nudges (Push Capa 3b): la curva de
intensidad, la ventana permitida (silencio + disponibilidad) y el texto
variado. Sin BD ni FCM."""
from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from app.matix.recordatorios import (
    intervalo_nudge,
    permitido_ahora,
    texto_nudge,
)

LIMA = ZoneInfo("America/Lima")
td = timedelta


def test_curva_escala_al_acercarse_con_tope():
    assert intervalo_nudge(td(days=5)) == td(hours=24)   # > 3 días: 1/día
    assert intervalo_nudge(td(hours=48)) == td(hours=12)
    assert intervalo_nudge(td(hours=10)) == td(hours=4)
    assert intervalo_nudge(td(hours=5)) == td(minutes=90)
    assert intervalo_nudge(td(hours=2)) == td(minutes=45)  # tope: 45 min
    # Vencida reciente sigue intenso; vencida vieja se detiene.
    assert intervalo_nudge(td(hours=-2)) == td(minutes=45)
    assert intervalo_nudge(td(hours=-30)) is None


def test_modo_prueba_comprime_a_minutos():
    assert intervalo_nudge(td(minutes=10), modo_prueba=True) == td(minutes=1)
    assert intervalo_nudge(td(hours=2), modo_prueba=True) == td(minutes=5)
    assert intervalo_nudge(td(hours=-2), modo_prueba=True) is None


_CFG = {
    "silencio_inicio": 22,
    "silencio_fin": 8,
    "disponibilidad": {
        str(d): {"activo": True, "inicio": 8, "fin": 22} for d in range(1, 8)
    },
}


def _lima(hora: int) -> datetime:
    return datetime(2026, 5, 30, hora, 0, tzinfo=LIMA)  # sábado (isoweekday 6)


def test_permitido_respeta_silencio_y_disponibilidad():
    assert permitido_ahora(_lima(10), _CFG) is True
    assert permitido_ahora(_lima(23), _CFG) is False  # dentro del silencio
    assert permitido_ahora(_lima(7), _CFG) is False   # antes de la ventana


def test_permitido_dia_inactivo():
    cfg = dict(_CFG)
    cfg["disponibilidad"] = {
        **_CFG["disponibilidad"],
        "6": {"activo": False, "inicio": 8, "fin": 22},
    }
    assert permitido_ahora(_lima(10), cfg) is False  # sábado inactivo


def test_texto_varia_y_usa_pool_urgente_al_final():
    a = texto_nudge("Tesis", td(days=2), 0)
    b = texto_nudge("Tesis", td(days=2), 1)
    assert a[0] == "Tesis"  # el título es la tarea
    assert a[1] != b[1]     # no repite consecutivo
    # En las últimas 3 h, otro tono (urgente).
    urgente = texto_nudge("Tesis", td(hours=1), 0)
    assert urgente[1] != texto_nudge("Tesis", td(days=2), 0)[1]
