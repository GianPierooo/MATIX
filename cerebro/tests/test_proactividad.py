"""Lógica pura del motor de proactividad (Capa 8): gatillos anticipatorios,
tope diario, adaptación al ritmo, dedup y puntaje. Sin BD ni FCM."""
from __future__ import annotations

from app.matix import proactividad as p


def test_params_por_nivel_con_default_exigente():
    assert p.params_nivel("suave")["tope_diario"] == 2
    assert p.params_nivel("equilibrado")["tope_diario"] == 4
    assert p.params_nivel("exigente")["tope_diario"] == 7
    # Nivel raro → cae a exigente (no rompe).
    assert p.params_nivel("???")["tope_diario"] == 7
    assert p.params_nivel(None)["tope_diario"] == 7
    # Suave no hace heads-up de plazos; exigente con el horizonte más amplio.
    assert p.params_nivel("suave")["deadline_horizonte_h"] == 0
    assert p.params_nivel("exigente")["deadline_horizonte_h"] == 72


def test_proximo_hueco_libre_dentro_de_la_ventana():
    bloques = [{"ini": 480, "fin": 540}, {"ini": 600, "fin": 660}]
    # Hueco 540–600 (60 min). A las 8:40 (520) faltan 20 min para que empiece →
    # dentro del lead de 30.
    h = p.proximo_hueco_libre(bloques, 520, lead_min=30)
    assert h == {"ini": 540, "dur": 60}
    # A las 8:00 (480) faltan 60 min → fuera del lead.
    assert p.proximo_hueco_libre(bloques, 480, lead_min=30) is None
    # Micro-hueco (< 30 min) no cuenta.
    pegados = [{"ini": 480, "fin": 540}, {"ini": 560, "fin": 600}]
    assert p.proximo_hueco_libre(pegados, 535, lead_min=30) is None


def test_hueco_actual_detecta_rato_libre_ahora():
    bloques = [{"ini": 480, "fin": 540}]
    # 9:20 (560): libre hasta dormir.
    assert p.hueco_actual(bloques, 560, 1380) == {"ini": 560, "dur": 820}
    # 8:30 (510): ocupado por el bloque.
    assert p.hueco_actual(bloques, 510, 1380) is None
    # Rato muy corto antes de dormir → None.
    assert p.hueco_actual([], 1370, 1380) is None


def test_necesita_reposicion_y_grueso_pendiente():
    assert p.necesita_reposicion(0) is True
    assert p.necesita_reposicion(1) is True
    assert p.necesita_reposicion(2) is False
    nodos = [
        {"granularidad": "grueso", "estado": "pendiente"},
        {"granularidad": "fino", "estado": "hecho"},
    ]
    assert p.hay_grueso_pendiente(nodos) is True
    assert p.hay_grueso_pendiente([{"granularidad": "grueso", "estado": "hecho"}]) is False
    assert p.hay_grueso_pendiente([{"granularidad": "fino", "estado": "pendiente"}]) is False


def test_urgencia_deadline_anticipa_zona_media_no_pisa_nudges():
    # Zona media (1 día..horizonte): heads-up anticipado.
    assert p.urgencia_deadline(40, horizonte_h=72) == "pronto"
    # < 24 h lo maneja el motor de nudges (no duplicar).
    assert p.urgencia_deadline(10, horizonte_h=72) is None
    # Más allá del horizonte del nivel: todavía no.
    assert p.urgencia_deadline(100, horizonte_h=72) is None
    # Nivel suave (horizonte 0): nunca avisa de plazos.
    assert p.urgencia_deadline(40, horizonte_h=0) is None


def test_tope_diario_y_dentro_de_tope():
    assert p.dentro_de_tope(3, 7) is True
    assert p.dentro_de_tope(7, 7) is False


def test_tope_ajustado_por_ritmo_baja_si_se_ignora():
    # Mandé varios y no hubo acción → recorto fuerte.
    assert p.tope_ajustado_por_ritmo(7, 4, 0) == 2
    # Mandé bastantes y casi nada de acción → recorto a la mitad.
    assert p.tope_ajustado_por_ritmo(7, 5, 1) == 3
    # Con acción / pocos envíos → no recorto.
    assert p.tope_ajustado_por_ritmo(7, 1, 0) == 7
    assert p.tope_ajustado_por_ritmo(7, 5, 3) == 7
    # Nunca baja de 1.
    assert p.tope_ajustado_por_ritmo(2, 4, 0) == 1


def test_clave_dedup_por_tema():
    assert p.clave_dedup("deadline", "t1") == "deadline:t1"
    assert p.clave_dedup("reposicion", "p9") == "reposicion:p9"


def test_puntaje_ordena_deadline_sobre_hueco():
    deadline = {"urgencia": 3, "oportunidad": 2, "relevancia": 3}
    hueco = {"urgencia": 1, "oportunidad": 2, "relevancia": 1}
    assert p.puntuar(deadline) > p.puntuar(hueco)
    assert p.puntuar(deadline) == 18


def test_textos_en_espanol_sin_asteriscos():
    for fn, args in [
        (p.texto_pre_libre, (60, "Práctica: Inglés")),
        (p.texto_hueco, (45, "OneXotic")),
        (p.texto_reposicion_lote, ("OneXotic", "Cerrar landing")),
        (p.texto_reposicion_fase, ("Matix 1.0",)),
        (p.texto_deadline, ("Entrega final", 40)),
        (p.texto_estancado_riesgo, ("OneXotic", 4)),
        (p.texto_dia_sobrecargado, (2,)),
        (p.texto_evaluacion_sin_estudio, ("Parcial 1", 3)),
        (p.texto_skill_descuidada, ("Inglés", 9)),
    ]:
        titulo, cuerpo = fn(*args)
        assert titulo and cuerpo
        assert "*" not in titulo and "*" not in cuerpo


# ── Detectores de RIESGO (Capa 8): disparan en su condición y NO fuera ───────


def test_estancado_temprano_solo_en_banda_3_a_5():
    assert p.estancado_temprano(3) is True
    assert p.estancado_temprano(4) is True
    # < 3 todavía no es riesgo; 5+ lo agarra el aviso sostenido de evolución.
    assert p.estancado_temprano(2) is False
    assert p.estancado_temprano(5) is False
    assert p.estancado_temprano(10) is False


def test_dia_sobrecargado_cuando_se_recorta_trabajo():
    assert p.dia_sobrecargado(0) is False  # nada quedó fuera → cabe
    assert p.dia_sobrecargado(1) is True   # algo de trabajo no entró
    assert p.dia_sobrecargado(3) is True


def test_evaluacion_en_riesgo_zona_1_a_7_sin_estudio():
    # En zona y sin estudio → dispara.
    assert p.evaluacion_en_riesgo(3, False) is True
    assert p.evaluacion_en_riesgo(1, False) is True
    assert p.evaluacion_en_riesgo(7, False) is True
    # Con estudio agendado → nunca molesta.
    assert p.evaluacion_en_riesgo(3, True) is False
    # < 1 día lo maneja nudges; > 7 días es muy pronto.
    assert p.evaluacion_en_riesgo(0, False) is False
    assert p.evaluacion_en_riesgo(8, False) is False


def test_skill_descuidada_tolerante():
    assert p.skill_descuidada(7) is True
    assert p.skill_descuidada(20) is True
    # Tolerante: un hobby puede dormir unos días sin culpa.
    assert p.skill_descuidada(6) is False
    assert p.skill_descuidada(0) is False


def test_scores_ordenan_riesgo_sobre_skill():
    # El día sobrecargado (hoy, accionable) pesa más que una skill descuidada.
    sobrecarga = {"urgencia": 3, "oportunidad": 3, "relevancia": 3}
    skill = {"urgencia": 1, "oportunidad": 2, "relevancia": 1}
    assert p.puntuar(sobrecarga) > p.puntuar(skill)
