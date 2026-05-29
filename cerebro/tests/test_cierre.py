"""Tests del cierre del día (Capa 8 · Paso 2).

Sembramos tareas (completadas hoy, pendientes de hoy, que vencen
mañana) y un evento de mañana; pedimos el cierre por HTTP y
verificamos que cada sección refleja lo correcto. Limpieza con
`/permanente`.

Lo central del paso: el tono es de cierre, no de exigencia. Los
tests verifican que `cierre_frase` nunca usa lenguaje de reproche
y que `texto_para_voz` arma prosa legible sin markdown.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from httpx import AsyncClient

from app.briefing import cierre as mod_cierre

_TZ_LIMA = timezone(timedelta(hours=-5))


def _hoy_lima_iso(hora: int, minuto: int = 0) -> str:
    ahora = datetime.now(timezone.utc).astimezone(_TZ_LIMA)
    dt = ahora.replace(hour=hora, minute=minuto, second=0, microsecond=0)
    return dt.astimezone(timezone.utc).isoformat()


def _manana_lima_iso(hora: int, minuto: int = 0) -> str:
    ahora = datetime.now(timezone.utc).astimezone(_TZ_LIMA)
    dt = (ahora + timedelta(days=1)).replace(
        hour=hora, minute=minuto, second=0, microsecond=0
    )
    return dt.astimezone(timezone.utc).isoformat()


async def test_cierre_arma_sin_romper(client: AsyncClient) -> None:
    r = await client.get("/api/v1/briefing/cierre")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["saludo"] == "Buenas noches"
    assert isinstance(body["hechas"], list)
    assert isinstance(body["pendientes_hoy"], list)
    assert isinstance(body["tareas_manana"], list)
    assert body["cierre_frase"]
    assert body["texto_para_voz"]
    assert body["resumen_corto"]


async def test_tarea_completada_hoy_aparece_en_hechas(
    client: AsyncClient,
) -> None:
    """Creamos una tarea y la completamos → debe salir en `hechas`."""
    r_t = await client.post(
        "/api/v1/tareas",
        json={
            "titulo": "_test_cierre_hecha",
            "vence_en": _hoy_lima_iso(15, 0),
        },
    )
    tid = r_t.json()["id"]
    try:
        # Completar la tarea. `completada_en` lo setea el cliente
        # (la app) al togglear — no hay trigger en BD. El cierre lo
        # usa para saber qué se completó HOY.
        r_p = await client.patch(
            f"/api/v1/tareas/{tid}",
            json={"completada": True, "completada_en": _hoy_lima_iso(20, 0)},
        )
        assert r_p.status_code == 200, r_p.text

        r = await client.get("/api/v1/briefing/cierre")
        body = r.json()
        titulos = [h["titulo"] for h in body["hechas"]]
        assert "_test_cierre_hecha" in titulos
    finally:
        await client.delete(f"/api/v1/tareas/{tid}/permanente")


async def test_pendiente_de_hoy_aparece_sin_drama(
    client: AsyncClient,
) -> None:
    """Tarea que vence hoy y NO está completada → pendientes_hoy."""
    r_t = await client.post(
        "/api/v1/tareas",
        json={
            "titulo": "_test_cierre_pendiente",
            "vence_en": _hoy_lima_iso(23, 0),
            "prioridad": "alta",
        },
    )
    tid = r_t.json()["id"]
    try:
        r = await client.get("/api/v1/briefing/cierre")
        body = r.json()
        titulos = [p["titulo"] for p in body["pendientes_hoy"]]
        assert "_test_cierre_pendiente" in titulos
    finally:
        await client.delete(f"/api/v1/tareas/{tid}/permanente")


async def test_lo_que_vence_manana(client: AsyncClient) -> None:
    """Tarea + evento de mañana entran en sus secciones."""
    r_t = await client.post(
        "/api/v1/tareas",
        json={
            "titulo": "_test_cierre_manana_tarea",
            "vence_en": _manana_lima_iso(10, 0),
        },
    )
    r_e = await client.post(
        "/api/v1/eventos",
        json={
            "titulo": "_test_cierre_manana_evento",
            "inicia_en": _manana_lima_iso(9, 0),
            "termina_en": _manana_lima_iso(10, 0),
        },
    )
    tid = r_t.json()["id"]
    eid = r_e.json()["id"]
    try:
        r = await client.get("/api/v1/briefing/cierre")
        body = r.json()
        assert "_test_cierre_manana_tarea" in [
            t["titulo"] for t in body["tareas_manana"]
        ]
        assert "_test_cierre_manana_evento" in [
            e["titulo"] for e in body["eventos_manana"]
        ]
    finally:
        await client.delete(f"/api/v1/tareas/{tid}/permanente")
        await client.delete(f"/api/v1/eventos/{eid}/permanente")


# ─── Tests puros del armador (sin BD) ───────────────────────────────


def test_frase_de_cierre_no_es_de_exigencia() -> None:
    """El tono nunca debe reprochar. Probamos las 4 combinaciones
    y verificamos ausencia de lenguaje de culpa."""
    palabras_prohibidas = ["deberías", "tenés que", "no hiciste", "falta", "urgente"]
    casos = [
        (3, 0),
        (3, 2),
        (0, 2),
        (0, 0),
    ]
    for n_hechas, n_pend in casos:
        frase = mod_cierre._frase_de_cierre(
            n_hechas=n_hechas, n_pendientes=n_pend
        )
        assert frase
        bajo = frase.lower()
        for p in palabras_prohibidas:
            assert p not in bajo, f"'{p}' aparece en: {frase}"


def test_frase_de_cierre_celebra_si_cerro_todo() -> None:
    frase = mod_cierre._frase_de_cierre(n_hechas=4, n_pendientes=0)
    assert "descans" in frase.lower()


def test_resumen_corto_cierre_vacio() -> None:
    assert (
        mod_cierre._resumen_corto_cierre(
            n_hechas=0, n_pendientes=0, n_manana=0
        )
        == "Repaso del día"
    )


def test_texto_voz_no_lleva_markdown() -> None:
    txt = mod_cierre._texto_voz_cierre(
        fecha_es="viernes 29 de mayo",
        hechas=[{"titulo": "TP3", "contexto": "Sistemas"}],
        pendientes_hoy=[{"titulo": "Leer cap 4", "prioridad": "media", "contexto": None}],
        tareas_manana=[{"titulo": "Entrega", "prioridad": "alta", "contexto": None}],
        eventos_manana=[{"hora": "09:00", "titulo": "Clase", "todo_el_dia": False}],
        cierre_frase="Soltá el día y descansá.",
    )
    assert "TP3" in txt
    assert "Clase" in txt
    assert "**" not in txt
    assert "- " not in txt
    assert txt.startswith("Buenas noches")
