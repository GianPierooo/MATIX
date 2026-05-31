"""Tests de la selección de rituales diarios (Push Capa 3a).

`rituales_due` es PURO: dado la config, los ya enviados hoy y `ahora`,
dice qué ritual toca. Cubre: hora exacta, catch-up dentro de la ventana,
dedupe del día, fuera de ventana, antes de hora y ritual desactivado.
"""
from __future__ import annotations

from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from app.matix.recordatorios import rituales_due

LIMA = ZoneInfo("America/Lima")

CFG = [
    {"ritual": "briefing", "activo": True, "hora": 8, "minuto": 0},
    {"ritual": "cierre", "activo": True, "hora": 22, "minuto": 0},
]


def _at(hora: int, minuto: int) -> datetime:
    """Un instante en hora de Lima, devuelto en UTC (como `ahora`)."""
    return datetime(2026, 5, 30, hora, minuto, tzinfo=LIMA).astimezone(timezone.utc)


def test_due_a_la_hora_exacta():
    assert rituales_due(CFG, set(), _at(8, 0)) == ["briefing"]
    assert rituales_due(CFG, set(), _at(22, 0)) == ["cierre"]


def test_catch_up_dentro_de_la_ventana():
    # 8:30: 30 min tarde, dentro de las 2h → todavía se manda.
    assert rituales_due(CFG, set(), _at(8, 30)) == ["briefing"]


def test_dedupe_no_reenvia_el_mismo_dia():
    assert rituales_due(CFG, {"briefing"}, _at(8, 0)) == []


def test_fuera_de_ventana_no_se_manda():
    # 11:00: más de 2h tarde para el briefing de las 8 → stale, no se manda.
    assert rituales_due(CFG, set(), _at(11, 0)) == []


def test_antes_de_la_hora_no_se_manda():
    assert rituales_due(CFG, set(), _at(7, 59)) == []


def test_ritual_desactivado_no_se_manda():
    cfg = [{"ritual": "briefing", "activo": False, "hora": 8, "minuto": 0}]
    assert rituales_due(cfg, set(), _at(8, 0)) == []


# ── repaso semanal (4º ritual, con dia_semana) ──────────────────────

from app.matix.recordatorios import _fecha_dedup  # noqa: E402

# 2026-05-31 es DOMINGO (isoweekday 7); 2026-05-30 SÁBADO (6).
REPASO = [
    {"ritual": "repaso", "activo": True, "hora": 20, "minuto": 0, "dia_semana": 7}
]


def _dom(hora: int, minuto: int) -> datetime:
    return datetime(2026, 5, 31, hora, minuto, tzinfo=LIMA).astimezone(timezone.utc)


def _sab(hora: int, minuto: int) -> datetime:
    return datetime(2026, 5, 30, hora, minuto, tzinfo=LIMA).astimezone(timezone.utc)


def test_repaso_solo_su_dia():
    # Domingo 20:00 → toca; sábado a la misma hora → no (no es su día).
    assert rituales_due(REPASO, set(), _dom(20, 0)) == ["repaso"]
    assert rituales_due(REPASO, set(), _sab(20, 0)) == []


def test_repaso_catch_up_y_ventana():
    # 1.5h tarde sigue dentro de la ventana de 2h.
    assert rituales_due(REPASO, set(), _dom(21, 30)) == ["repaso"]
    # 2.5h tarde → fuera de ventana.
    assert rituales_due(REPASO, set(), _dom(22, 30)) == []
    # Antes de la hora → no.
    assert rituales_due(REPASO, set(), _dom(19, 59)) == []


def test_repaso_dedupe_y_off():
    assert rituales_due(REPASO, {"repaso"}, _dom(20, 0)) == []
    off = [{"ritual": "repaso", "activo": False, "hora": 20, "minuto": 0,
            "dia_semana": 7}]
    assert rituales_due(off, set(), _dom(20, 0)) == []


def test_fecha_dedup_semanal_es_lunes_de_la_semana():
    dom = datetime(2026, 5, 31, 20, 0, tzinfo=LIMA)  # domingo
    # Lunes de esa semana ISO = 2026-05-25.
    assert _fecha_dedup(REPASO[0], dom) == "2026-05-25"
    # Un ritual diario usa el día mismo.
    assert _fecha_dedup(CFG[0], dom) == "2026-05-31"
