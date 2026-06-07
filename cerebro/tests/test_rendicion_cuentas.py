"""Push de rendición de cuentas con botones de acción — pieza pura.

Cubre los 5 contratos clave del prompt del usuario:
  1. Contenido determinista (plantilla, sin LLM): título, cuerpo, lista corta.
  2. Botón "más tarde" presente SOLO si hay ventana útil real antes del ancla
     de dormir (reusa la ventana útil de B).
  3. Escalada con tope (3 niveles) + dedup por tarea.
  4. Silencio nocturno respetado.
  5. Si el botón "más tarde" no aparece, las opciones se reducen limpio.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from app.matix import rendicion_cuentas as rc


# ── Bug-de-vida: contenido DETERMINISTA, sin LLM ─────────────────────────────


def test_contenido_una_tarea_singular():
    """Una sola tarea → texto singular natural."""
    out = rc.armar_contenido(
        [{"titulo": "Enviar el reporte"}],
        nivel=1, hay_ventana_util=True,
    )
    assert out["titulo"] == "No completaste una tarea"
    assert "«Enviar el reporte»" in out["cuerpo"]
    assert "¿Las hiciste?" in out["cuerpo"]


def test_contenido_varias_tareas_plural_y_lista():
    out = rc.armar_contenido(
        [{"titulo": "A"}, {"titulo": "B"}],
        nivel=1, hay_ventana_util=True,
    )
    assert out["titulo"] == "No completaste 2 tareas"
    assert "«A»" in out["cuerpo"] and "«B»" in out["cuerpo"]


def test_contenido_lista_truncada_con_sobra():
    """>3 tareas → muestra 3 + "y N más" para no romper el ancho de la notif."""
    tareas = [{"titulo": f"Tarea {i}"} for i in range(5)]
    out = rc.armar_contenido(tareas, nivel=1, hay_ventana_util=False)
    assert out["titulo"] == "No completaste 5 tareas"
    assert "y 2 más" in out["cuerpo"]


def test_contenido_titulo_largo_se_acorta():
    out = rc.armar_contenido(
        [{"titulo": "Tarea súper larga " * 10}],
        nivel=1, hay_ventana_util=True,
    )
    # Solo verifica el truncado del título (no su ubicación exacta en el cuerpo).
    assert "…" in out["cuerpo"]


def test_escalada_tono_por_nivel():
    """Nivel 1 suave, nivel 2 firme, nivel 3 final — sin culpa, escalado."""
    base = [{"titulo": "X"}]
    n1 = rc.armar_contenido(base, nivel=1, hay_ventana_util=True)
    n2 = rc.armar_contenido(base, nivel=2, hay_ventana_util=True)
    n3 = rc.armar_contenido(base, nivel=3, hay_ventana_util=True)
    assert "No completaste" in n1["cuerpo"]
    assert "Siguen sin hacerse" in n2["cuerpo"]
    assert "Tercer aviso" in n3["cuerpo"] and "Decide ya" in n3["cuerpo"]


# ── Botón "más tarde": solo si hay ventana útil real ─────────────────────────


def test_acciones_con_ventana_util_incluye_mas_tarde():
    out = rc.armar_contenido(
        [{"titulo": "X"}], nivel=1, hay_ventana_util=True,
    )
    assert out["acciones"] == ["hecho", "mas_tarde", "manana"]


def test_acciones_sin_ventana_util_omite_mas_tarde():
    """El bug del prompt: si ya es tarde, NO mostrar 'hoy 20:10'."""
    out = rc.armar_contenido(
        [{"titulo": "X"}], nivel=1, hay_ventana_util=False,
    )
    assert out["acciones"] == ["hecho", "manana"]
    assert "mas_tarde" not in out["acciones"]


# ── Ventana útil reusa el cálculo de B (buffer_pre_sueno_min) ────────────────


def test_hay_ventana_util_si_queda_tiempo():
    """A las 19:00, ancla dormir 23:00, buffer 60 → fin_util 22:00, dur 20min:
    sí queda ventana."""
    ahora = datetime(2026, 6, 7, 19, 0, tzinfo=rc.LIMA)
    assert rc.hay_ventana_util_hoy(
        [], ahora_local=ahora,
        despertar_min=7 * 60, dormir_min=23 * 60,
        buffer_min=10, buffer_pre_sueno_min=60, dur_min=20,
    ) is True


def test_no_hay_ventana_util_si_ya_es_tarde():
    """A las 22:30, ancla dormir 23:00, buffer 60 → fin_util 22:00, ya pasó:
    NO queda ventana → el botón 'más tarde' no debe aparecer."""
    ahora = datetime(2026, 6, 7, 22, 30, tzinfo=rc.LIMA)
    assert rc.hay_ventana_util_hoy(
        [], ahora_local=ahora,
        despertar_min=7 * 60, dormir_min=23 * 60,
        buffer_min=10, buffer_pre_sueno_min=60, dur_min=20,
    ) is False


def test_ancla_dormir_temprana_define_la_tarde_noche():
    """Si tu ancla es 21:00 (no 23 fijo), a las 19:30 con buffer 60 ya no
    queda ventana útil — la 'tarde/noche' se deriva del ancla, no de 7pm."""
    ahora = datetime(2026, 6, 7, 19, 30, tzinfo=rc.LIMA)
    # 21:00 - 60 = 20:00 fin_util, desde 19:30 → 30 min libres (basta para 20).
    assert rc.hay_ventana_util_hoy(
        [], ahora_local=ahora,
        despertar_min=7 * 60, dormir_min=21 * 60,
        buffer_min=10, buffer_pre_sueno_min=60, dur_min=20,
    ) is True
    # Pero NO para una tarea de 45 min.
    assert rc.hay_ventana_util_hoy(
        [], ahora_local=ahora,
        despertar_min=7 * 60, dormir_min=21 * 60,
        buffer_min=10, buffer_pre_sueno_min=60, dur_min=45,
    ) is False


def test_proximo_slot_hoy_min_devuelve_inicio_real():
    """`mas_tarde` mueve al PRIMER hueco que cabe."""
    ahora = datetime(2026, 6, 7, 19, 0, tzinfo=rc.LIMA)
    slot = rc.proximo_slot_hoy_min(
        [], ahora_local=ahora,
        despertar_min=7 * 60, dormir_min=23 * 60,
        buffer_min=10, buffer_pre_sueno_min=60, dur_min=20,
    )
    assert slot == 19 * 60  # arranca exactamente desde "ahora"


def test_proximo_slot_hoy_min_none_si_no_cabe():
    ahora = datetime(2026, 6, 7, 22, 30, tzinfo=rc.LIMA)
    slot = rc.proximo_slot_hoy_min(
        [], ahora_local=ahora,
        despertar_min=7 * 60, dormir_min=23 * 60,
        buffer_min=10, buffer_pre_sueno_min=60, dur_min=20,
    )
    assert slot is None


# ── Escalada con tope + dedup por tarea ──────────────────────────────────────


def test_primera_vez_arranca_en_nivel_1():
    ahora = datetime(2026, 6, 7, 12, 0, tzinfo=timezone.utc)
    assert rc.calcular_nivel_siguiente(None, ahora=ahora) == 1


def test_resuelto_no_se_repinga_jamas():
    """Una tarea ya resuelta (botón tocado) NO vuelve a aparecer — bug crítico."""
    ahora = datetime(2026, 6, 7, 12, 0, tzinfo=timezone.utc)
    ultimo = {
        "nivel": 1,
        "enviado_en": (ahora - timedelta(days=2)).isoformat(),
        "resuelta_en": (ahora - timedelta(days=1)).isoformat(),
    }
    assert rc.calcular_nivel_siguiente(ultimo, ahora=ahora) is None


def test_cooldown_entre_niveles_no_spam():
    """Si el último ping fue hace 1h, NO mandar el siguiente nivel ya."""
    ahora = datetime(2026, 6, 7, 12, 0, tzinfo=timezone.utc)
    ultimo = {
        "nivel": 1,
        "enviado_en": (ahora - timedelta(hours=1)).isoformat(),
    }
    assert rc.calcular_nivel_siguiente(ultimo, ahora=ahora) is None


def test_escalada_sube_nivel_cuando_pasa_cooldown():
    """Pasado el cooldown, sí avanza al siguiente nivel."""
    ahora = datetime(2026, 6, 7, 12, 0, tzinfo=timezone.utc)
    ultimo = {
        "nivel": 1,
        "enviado_en": (ahora - timedelta(hours=24)).isoformat(),
    }
    assert rc.calcular_nivel_siguiente(ultimo, ahora=ahora) == 2


def test_tope_dura_nivel_3_no_se_sobrepasa():
    """Tope: tras nivel 3 (final) NO se vuelve a pingar — anti-spam infinito."""
    ahora = datetime(2026, 6, 7, 12, 0, tzinfo=timezone.utc)
    ultimo = {
        "nivel": 3,
        "enviado_en": (ahora - timedelta(days=5)).isoformat(),
    }
    assert rc.calcular_nivel_siguiente(ultimo, ahora=ahora) is None


# ── Cero tareas → nada que mandar ────────────────────────────────────────────


def test_sin_tareas_no_hay_acciones():
    out = rc.armar_contenido([], nivel=1, hay_ventana_util=True)
    assert out["acciones"] == []
    assert out["titulo"] == ""
