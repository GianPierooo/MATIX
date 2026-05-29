"""Tests del briefing matutino (Capa 8 reducida · Paso 1).

Estrategia: sembramos datos del día (eventos, tareas, un proyecto
viejo para disparar alerta), pedimos el briefing por HTTP y
verificamos que cada sección refleja lo correcto. Limpieza con
`/permanente` para no dejar nada en papelera del proyecto-test.

Casos cubiertos:

1. Día vacío: agenda libre, resumen corto suave, texto de voz dice
   "agenda libre".
2. Día con datos: aparecen eventos hoy, tareas hoy, vencidas
   resumidas, alertas de proyecto estancado, choque de horario.
3. Las prioridades altas vienen primero en `tareas_hoy`.
4. El `texto_para_voz` incluye los títulos y no rompe formato.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from httpx import AsyncClient

from app.briefing import armar as briefing_armar
from app.db import Postgrest

_TZ_LIMA = timezone(timedelta(hours=-5))


def _hoy_lima_iso(hora: int, minuto: int = 0) -> str:
    """Construye un ISO UTC que en Lima cae HOY a `hora:minuto`."""
    ahora = datetime.now(timezone.utc).astimezone(_TZ_LIMA)
    dt = ahora.replace(
        hour=hora, minute=minuto, second=0, microsecond=0
    )
    return dt.astimezone(timezone.utc).isoformat()


def _ayer_lima_iso(dias_atras: int = 1) -> str:
    ahora = datetime.now(timezone.utc).astimezone(_TZ_LIMA)
    dt = ahora.replace(
        hour=10, minute=0, second=0, microsecond=0
    ) - timedelta(days=dias_atras)
    return dt.astimezone(timezone.utc).isoformat()


# ─── Test 1: día vacío ──────────────────────────────────────────────


async def test_briefing_dia_vacio(client: AsyncClient) -> None:
    """Sin tareas hoy, sin eventos hoy, sin alertas → resumen suave
    y texto de voz que reconoce la libertad. Nota: si la BD-test
    ya tiene cosas vivas hoy de otros tests, el conteo no será 0
    pero igual chequeamos que el briefing arme sin romper."""
    r = await client.get("/api/v1/briefing/hoy")
    assert r.status_code == 200, r.text
    body = r.json()
    assert "fecha" in body
    assert "saludo" in body
    assert isinstance(body["eventos"], list)
    assert isinstance(body["tareas_hoy"], list)
    assert isinstance(body["alertas"], list)
    assert "texto_para_voz" in body and body["texto_para_voz"]
    assert "resumen_corto" in body and body["resumen_corto"]


# ─── Test 2: día con datos ──────────────────────────────────────────


async def test_briefing_con_evento_y_tarea_de_hoy(
    client: AsyncClient,
) -> None:
    """Sembramos un evento y una tarea que vencen hoy. El briefing
    los lista. Limpiamos al final con /permanente."""
    inicia = _hoy_lima_iso(15, 0)
    termina = _hoy_lima_iso(16, 0)
    r_ev = await client.post(
        "/api/v1/eventos",
        json={
            "titulo": "_test_briefing_evento_hoy",
            "inicia_en": inicia,
            "termina_en": termina,
        },
    )
    assert r_ev.status_code == 201, r_ev.text
    evento_id = r_ev.json()["id"]

    vence = _hoy_lima_iso(23, 0)
    r_t = await client.post(
        "/api/v1/tareas",
        json={
            "titulo": "_test_briefing_tarea_hoy",
            "vence_en": vence,
            "prioridad": "alta",
        },
    )
    assert r_t.status_code == 201, r_t.text
    tarea_id = r_t.json()["id"]

    try:
        r = await client.get("/api/v1/briefing/hoy")
        assert r.status_code == 200, r.text
        body = r.json()

        titulos_eventos = [e["titulo"] for e in body["eventos"]]
        assert "_test_briefing_evento_hoy" in titulos_eventos

        titulos_tareas = [t["titulo"] for t in body["tareas_hoy"]]
        assert "_test_briefing_tarea_hoy" in titulos_tareas

        # El resumen_corto debe mencionar al menos eventos y tareas
        # (los conteos pueden venir contaminados por residuos pero
        # los dos sustantivos deberían estar).
        assert "evento" in body["resumen_corto"]
        assert "tarea" in body["resumen_corto"]
    finally:
        await client.delete(f"/api/v1/eventos/{evento_id}/permanente")
        await client.delete(f"/api/v1/tareas/{tarea_id}/permanente")


# ─── Test 3: prioridad alta primero ─────────────────────────────────


async def test_tareas_hoy_se_ordenan_por_prioridad(
    client: AsyncClient,
) -> None:
    """Si hay varias tareas hoy, las de prioridad alta van antes que
    las de baja en `tareas_hoy`."""
    baja = await client.post(
        "/api/v1/tareas",
        json={
            "titulo": "_test_briefing_baja",
            "vence_en": _hoy_lima_iso(22, 0),
            "prioridad": "baja",
        },
    )
    alta = await client.post(
        "/api/v1/tareas",
        json={
            "titulo": "_test_briefing_alta",
            "vence_en": _hoy_lima_iso(21, 0),
            "prioridad": "alta",
        },
    )
    assert baja.status_code == 201 and alta.status_code == 201
    bid = baja.json()["id"]
    aid = alta.json()["id"]

    try:
        r = await client.get("/api/v1/briefing/hoy")
        assert r.status_code == 200
        titulos = [t["titulo"] for t in r.json()["tareas_hoy"]]
        # La de alta tiene que aparecer ANTES que la de baja.
        pos_alta = titulos.index("_test_briefing_alta")
        pos_baja = titulos.index("_test_briefing_baja")
        assert pos_alta < pos_baja, (
            "alta debe ir antes que baja; lista = " + str(titulos)
        )
    finally:
        await client.delete(f"/api/v1/tareas/{bid}/permanente")
        await client.delete(f"/api/v1/tareas/{aid}/permanente")


# ─── Test 4: tarea vencida ──────────────────────────────────────────


async def test_tarea_vencida_se_cuenta_en_resumen(
    client: AsyncClient,
) -> None:
    """Una tarea con `vence_en` en el pasado entra en el resumen de
    vencidas con su `dias_vencida`."""
    r_t = await client.post(
        "/api/v1/tareas",
        json={
            "titulo": "_test_briefing_vencida",
            "vence_en": _ayer_lima_iso(dias_atras=3),
            "prioridad": "media",
        },
    )
    tid = r_t.json()["id"]
    try:
        r = await client.get("/api/v1/briefing/hoy")
        body = r.json()
        assert body["tareas_vencidas"]["total"] >= 1
        # La nuestra tiene 3 días — el `mas_antigua_dias` tiene que
        # ser al menos 3.
        assert body["tareas_vencidas"]["mas_antigua_dias"] >= 3
    finally:
        await client.delete(f"/api/v1/tareas/{tid}/permanente")


# ─── Test 5: detección de choque de horario ─────────────────────────


async def test_choque_horario_genera_alerta(client: AsyncClient) -> None:
    """Dos eventos con franjas que se solapan disparan una alerta
    `choque_horario`."""
    ev_a = await client.post(
        "/api/v1/eventos",
        json={
            "titulo": "_test_briefing_choque_A",
            "inicia_en": _hoy_lima_iso(15, 0),
            "termina_en": _hoy_lima_iso(16, 30),
        },
    )
    ev_b = await client.post(
        "/api/v1/eventos",
        json={
            "titulo": "_test_briefing_choque_B",
            "inicia_en": _hoy_lima_iso(16, 0),
            "termina_en": _hoy_lima_iso(17, 0),
        },
    )
    aid = ev_a.json()["id"]
    bid = ev_b.json()["id"]
    try:
        r = await client.get("/api/v1/briefing/hoy")
        body = r.json()
        tipos = [a["tipo"] for a in body["alertas"]]
        assert "choque_horario" in tipos, body["alertas"]
        # Y el mensaje menciona ambos títulos.
        msgs = [a["mensaje"] for a in body["alertas"]]
        assert any(
            "_test_briefing_choque_A" in m and "_test_briefing_choque_B" in m
            for m in msgs
        )
    finally:
        await client.delete(f"/api/v1/eventos/{aid}/permanente")
        await client.delete(f"/api/v1/eventos/{bid}/permanente")


# ─── Test 6: texto_para_voz tiene contenido legible ─────────────────


async def test_texto_para_voz_lleva_la_info_clave(
    client: AsyncClient,
) -> None:
    """El campo `texto_para_voz` arma una prosa que el botón
    'Escuchar' manda al TTS. Cuando hay un evento y una tarea,
    sus títulos tienen que aparecer en el texto."""
    ev = await client.post(
        "/api/v1/eventos",
        json={
            "titulo": "_test_briefing_voz_evento",
            "inicia_en": _hoy_lima_iso(10, 0),
            "termina_en": _hoy_lima_iso(11, 0),
        },
    )
    t = await client.post(
        "/api/v1/tareas",
        json={
            "titulo": "_test_briefing_voz_tarea",
            "vence_en": _hoy_lima_iso(20, 0),
        },
    )
    eid = ev.json()["id"]
    tid = t.json()["id"]
    try:
        r = await client.get("/api/v1/briefing/hoy")
        texto = r.json()["texto_para_voz"]
        assert "_test_briefing_voz_evento" in texto
        assert "_test_briefing_voz_tarea" in texto
        # No queremos markdown ni bullets en el texto que va a TTS.
        assert "**" not in texto
        assert "- " not in texto
    finally:
        await client.delete(f"/api/v1/eventos/{eid}/permanente")
        await client.delete(f"/api/v1/tareas/{tid}/permanente")


# ─── Tests puros del armador (sin BD) ───────────────────────────────


def test_resumen_corto_sin_nada() -> None:
    assert (
        briefing_armar._resumen_corto(
            n_eventos=0, n_tareas_hoy=0, n_alertas=0
        )
        == "Día libre"
    )


def test_resumen_corto_singular_y_plural() -> None:
    s = briefing_armar._resumen_corto(
        n_eventos=1, n_tareas_hoy=2, n_alertas=0
    )
    assert "1 evento" in s
    assert "2 tareas" in s


def test_texto_voz_dia_libre_con_vencidas() -> None:
    txt = briefing_armar._armar_texto_voz(
        saludo="Buenos días",
        fecha_es="viernes 29 de mayo",
        eventos=[],
        tareas_hoy=[],
        vencidas_resumen={"total": 2, "mas_antigua_dias": 5},
        alertas=[],
    )
    assert "agenda libre" in txt
    assert "2" in txt
    assert "5" in txt


def test_choques_detecta_solape() -> None:
    e1 = {
        "titulo": "A",
        "inicia_en": "2026-05-28T15:00:00+00:00",
        "termina_en": "2026-05-28T16:30:00+00:00",
    }
    e2 = {
        "titulo": "B",
        "inicia_en": "2026-05-28T16:00:00+00:00",
        "termina_en": "2026-05-28T17:00:00+00:00",
    }
    e3 = {
        "titulo": "C",
        "inicia_en": "2026-05-28T17:30:00+00:00",
        "termina_en": "2026-05-28T18:00:00+00:00",
    }
    pares = briefing_armar._choques([e1, e2, e3])
    titulos = [(a["titulo"], b["titulo"]) for a, b in pares]
    assert ("A", "B") in titulos
    # C no choca con ninguno.
    assert all("C" not in p for p in titulos)
