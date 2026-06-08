"""Notis proactivas programadas (módulo PURO).

Coberturas críticas:
- Resumen matutino aparece solo si la hora del resumen está EN FUTURO.
- Pre-actividad por cada bloque con lead correcto y formato esperado.
- Nudges del "próximo bloque" dosificados por dial (suave→máximo).
- Quiet hours BLOQUEAN cualquier noti que caería ahí.
- Notas pasadas NO se programan.
- Dedup_key estable: armar dos veces con el MISMO input da exactamente las
  mismas keys (la app puede dedup-cancelar idempotente).
"""
from __future__ import annotations

from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from app.matix import notis_programadas as np

LIMA = ZoneInfo("America/Lima")


def _lima(h: int, m: int = 0) -> datetime:
    """Helper: 2026-06-08 HH:MM en Lima, convertido a UTC aware."""
    return datetime(2026, 6, 8, h, m, tzinfo=LIMA).astimezone(timezone.utc)


def _plan(bloques: list[dict] | None = None, despierta: str | None = "06:30") -> dict:
    return {
        "fecha": "2026-06-08",
        "despierta": despierta,
        "duerme": "23:00",
        "bloques": bloques or [],
    }


def _cfg(**kwargs) -> dict:
    base = {"intensidad": "intenso", "silencio_inicio": 22, "silencio_fin": 8}
    base.update(kwargs)
    return base


# ── Resumen matutino ────────────────────────────────────────────────────────


def test_resumen_matutino_se_programa_si_es_futuro():
    # Ahora = 05:00 Lima. Despertar marcado 06:30 → resumen a 06:35.
    ahora = _lima(5, 0)
    notis = np.armar_notis_programadas(_plan(), _cfg(), ahora=ahora)
    resumen = [n for n in notis if n.tipo == "resumen_matutino"]
    assert len(resumen) == 1
    n = resumen[0]
    assert n.titulo == "Tu día"
    # 06:30 + 5 min = 06:35.
    assert n.disparar_en.astimezone(LIMA).strftime("%H:%M") == "06:35"
    assert n.dedup_key == "resumen_matutino|2026-06-08"


def test_resumen_matutino_no_se_programa_si_ya_paso():
    # Ahora = 10:00 Lima — ya pasó la hora del resumen.
    ahora = _lima(10, 0)
    notis = np.armar_notis_programadas(_plan(), _cfg(), ahora=ahora)
    assert not [n for n in notis if n.tipo == "resumen_matutino"]


def test_resumen_matutino_cuerpo_lista_bloques_corto():
    bloques = [
        {"inicio": "09:00", "fin": "09:30", "titulo": "calistenia", "tipo": "fijo"},
        {"inicio": "11:00", "fin": "12:00", "titulo": "inglés", "tipo": "trabajo"},
        {"inicio": "18:00", "fin": "19:00", "titulo": "taller", "tipo": "fijo"},
    ]
    ahora = _lima(5, 0)
    notis = np.armar_notis_programadas(_plan(bloques=bloques), _cfg(), ahora=ahora)
    resumen = next(n for n in notis if n.tipo == "resumen_matutino")
    assert "09:00 calistenia" in resumen.cuerpo
    assert "11:00 inglés" in resumen.cuerpo
    assert "18:00 taller" in resumen.cuerpo


def test_resumen_matutino_dia_vacio_aun_invita():
    ahora = _lima(5, 0)
    notis = np.armar_notis_programadas(_plan(bloques=[]), _cfg(), ahora=ahora)
    resumen = next(n for n in notis if n.tipo == "resumen_matutino")
    assert "Sin bloques" in resumen.cuerpo or "armar tu día" in resumen.cuerpo.lower()


# ── Pre-actividad ───────────────────────────────────────────────────────────


def test_pre_actividad_se_programa_lead_min_antes_de_cada_bloque():
    bloques = [
        {"inicio": "11:00", "fin": "12:00", "titulo": "Inglés bloque 4", "tipo": "trabajo"},
        {"inicio": "18:00", "fin": "19:00", "titulo": "Taller guitarra", "tipo": "fijo"},
    ]
    ahora = _lima(7, 0)
    notis = np.armar_notis_programadas(_plan(bloques=bloques), _cfg(), ahora=ahora)
    pre = [n for n in notis if n.tipo == "pre_actividad"]
    assert len(pre) == 2
    # 11:00 - 15 min = 10:45; 18:00 - 15 min = 17:45.
    horas_locales = [n.disparar_en.astimezone(LIMA).strftime("%H:%M") for n in pre]
    assert "10:45" in horas_locales
    assert "17:45" in horas_locales
    titulos = [n.titulo for n in pre]
    assert any("Inglés bloque 4" in t for t in titulos)
    assert any("Taller guitarra" in t for t in titulos)
    assert all("En 15 min" in t for t in titulos)


def test_pre_actividad_respeta_pre_actividad_min_override():
    bloques = [{"inicio": "11:00", "titulo": "Inglés", "tipo": "trabajo"}]
    ahora = _lima(7, 0)
    notis = np.armar_notis_programadas(
        _plan(bloques=bloques), _cfg(pre_actividad_min=10), ahora=ahora
    )
    pre = next(n for n in notis if n.tipo == "pre_actividad")
    assert pre.disparar_en.astimezone(LIMA).strftime("%H:%M") == "10:50"
    assert "En 10 min" in pre.titulo


def test_pre_actividad_no_programa_bloques_pasados():
    bloques = [
        {"inicio": "09:00", "titulo": "ya pasó", "tipo": "fijo"},
        {"inicio": "15:00", "titulo": "futuro", "tipo": "trabajo"},
    ]
    ahora = _lima(12, 0)
    notis = np.armar_notis_programadas(_plan(bloques=bloques), _cfg(), ahora=ahora)
    pre = [n for n in notis if n.tipo == "pre_actividad"]
    assert len(pre) == 1
    assert "futuro" in pre[0].titulo


def test_pre_actividad_dedup_key_estable_entre_invocaciones():
    """Re-pedir con el MISMO input devuelve los mismos dedup_key — la app puede
    cancelar idempotente sin acumular alarmas duplicadas."""
    bloques = [{"inicio": "11:00", "titulo": "Inglés", "tipo": "trabajo",
                "set_item_id": "abc-123"}]
    ahora = _lima(7, 0)
    notis_a = np.armar_notis_programadas(_plan(bloques=bloques), _cfg(), ahora=ahora)
    notis_b = np.armar_notis_programadas(_plan(bloques=bloques), _cfg(), ahora=ahora)
    keys_a = sorted(n.dedup_key for n in notis_a)
    keys_b = sorted(n.dedup_key for n in notis_b)
    assert keys_a == keys_b


# ── Nudges proximo + dial de intensidad ─────────────────────────────────────


def test_nudges_proximo_dosificados_por_dial():
    bloques = [
        {"inicio": "11:00", "titulo": "A", "tipo": "trabajo"},
        {"inicio": "15:00", "titulo": "B", "tipo": "trabajo"},
        {"inicio": "19:00", "titulo": "C", "tipo": "fijo"},
    ]
    ahora = _lima(9, 0)  # solo cuentan horas 11/13/15/17/19 futuro

    def _nudges(intensidad: str) -> int:
        notis = np.armar_notis_programadas(
            _plan(bloques=bloques), _cfg(intensidad=intensidad), ahora=ahora,
        )
        return len([n for n in notis if n.tipo == "nudge_proximo"])

    # En suave: 1 nudge; medio: 2; intenso: 3; maximo: 5 (de las 5 horas
    # válidas, todas a futuro desde las 9:00).
    assert _nudges("suave") == 1
    assert _nudges("medio") == 2
    assert _nudges("intenso") == 3
    assert _nudges("maximo") == 5


def test_nudge_proximo_cita_el_siguiente_bloque_pendiente():
    bloques = [
        {"inicio": "09:00", "titulo": "ya hecho", "tipo": "fijo"},
        {"inicio": "15:00", "titulo": "estudio inglés", "tipo": "trabajo"},
        {"inicio": "19:00", "titulo": "guitarra", "tipo": "fijo"},
    ]
    ahora = _lima(10, 0)
    notis = np.armar_notis_programadas(
        _plan(bloques=bloques), _cfg(intensidad="suave"), ahora=ahora,
    )
    nudges = [n for n in notis if n.tipo == "nudge_proximo"]
    assert len(nudges) == 1
    # Nudge a las 11:00, próximo bloque pendiente: 15:00 estudio inglés.
    assert "estudio inglés" in nudges[0].titulo
    assert "15:00" in nudges[0].cuerpo


def test_nudge_neutro_si_no_queda_nada_pendiente():
    # Bloques solo en la mañana, nudge a las 13:00 → no hay nada después.
    bloques = [{"inicio": "08:00", "titulo": "única", "tipo": "fijo"}]
    ahora = _lima(11, 0)
    notis = np.armar_notis_programadas(
        _plan(bloques=bloques), _cfg(intensidad="suave"), ahora=ahora,
    )
    nudges = [n for n in notis if n.tipo == "nudge_proximo"]
    assert len(nudges) == 1
    # Mensaje neutro cuando no queda nada.
    assert "libre" in nudges[0].titulo.lower()


# ── Quiet hours ─────────────────────────────────────────────────────────────


def test_quiet_hours_bloquean_pre_actividad():
    # silencio 22 → 8. Un bloque a las 7:50 → pre 7:35 cae en silencio.
    bloques = [{"inicio": "07:50", "titulo": "early", "tipo": "fijo"}]
    ahora = _lima(5, 0)
    notis = np.armar_notis_programadas(
        _plan(bloques=bloques), _cfg(silencio_inicio=22, silencio_fin=8),
        ahora=ahora,
    )
    pre = [n for n in notis if n.tipo == "pre_actividad"]
    assert not pre  # bloqueada por silencio


def test_quiet_hours_filtran_horario_nudges():
    # Silencio 18→8 (extra-extendido, cruza medianoche → silencio = h≥18 OR h<8).
    # De las 5 horas del HORARIO_NUDGES (11/13/15/17/19), 19 cae en silencio.
    # Las otras 4 sobreviven. Con dial=maximo cabrían 5 pero solo hay 4 válidas.
    ahora = _lima(5, 0)
    notis = np.armar_notis_programadas(
        _plan(), _cfg(intensidad="maximo", silencio_inicio=18, silencio_fin=8),
        ahora=ahora,
    )
    nudges = [n for n in notis if n.tipo == "nudge_proximo"]
    horas = [n.disparar_en.astimezone(LIMA).hour for n in nudges]
    assert sorted(horas) == [11, 13, 15, 17]
    assert 19 not in horas


# ── Orden cronológico ───────────────────────────────────────────────────────


def test_notis_devueltas_ordenadas_por_disparar_en():
    bloques = [
        {"inicio": "11:00", "titulo": "A", "tipo": "trabajo"},
        {"inicio": "18:00", "titulo": "B", "tipo": "fijo"},
    ]
    ahora = _lima(5, 0)
    notis = np.armar_notis_programadas(_plan(bloques=bloques), _cfg(), ahora=ahora)
    tiempos = [n.disparar_en for n in notis]
    assert tiempos == sorted(tiempos)


# ── Serialización ───────────────────────────────────────────────────────────


def test_to_dict_lleva_iso_y_campos_esperados():
    bloques = [{"inicio": "11:00", "titulo": "X", "tipo": "trabajo"}]
    ahora = _lima(5, 0)
    notis = np.armar_notis_programadas(_plan(bloques=bloques), _cfg(), ahora=ahora)
    d = notis[0].to_dict()
    for k in ("tipo", "dedup_key", "disparar_en", "titulo", "cuerpo", "payload"):
        assert k in d
    # disparar_en es ISO string parseable.
    assert datetime.fromisoformat(d["disparar_en"])
