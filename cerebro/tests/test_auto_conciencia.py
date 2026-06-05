"""Matix sabe el estado de su propio proyecto: ESTADO.md + CHECKLIST_1.0.md
viajan en el system prompt, y la tool `obtener_cambios_recientes` devuelve git
log real. Los tres intents del chat (qué se actualizó / qué falta para 1.0 /
qué atacar ahora) tienen el material para responder con datos reales."""
from __future__ import annotations

import pytest

from app.matix.system_prompt import system_prompt_fijo
from app.matix.tools import (
    TABLAS_AFECTADAS,
    TOOL_DEFINITIONS,
    ejecutar_tool,
    parsear_git_log,
)


# ── System prompt: ambos archivos llegan al chat como contexto fresco ──────


def test_system_prompt_incluye_ESTADO_md():
    p = system_prompt_fijo()
    # Header literal del archivo: si está, lo leyó sin errores.
    assert "ESTADO.md:" in p
    assert "INVENTARIO" in p, "el contenido real de ESTADO.md debería estar"


def test_system_prompt_incluye_CHECKLIST_1_0():
    p = system_prompt_fijo()
    assert "CHECKLIST_1.0.md:" in p
    # Las tres secciones honestas que la 1.0 nombra explícitamente.
    assert "Hecho" in p
    assert "Falta para 1.0" in p
    assert "Post-1.0" in p


def test_system_prompt_orienta_los_tres_intents():
    """Las tres preguntas de auto-conciencia tienen instrucción explícita."""
    p = system_prompt_fijo()
    bajo = p.lower()
    assert "qué se actualizó" in bajo
    assert "qué falta para 1.0" in bajo
    assert "qué me sugieres atacar ahora" in bajo


def test_polish_ui_marcado_post_1_0_explicito():
    """Sugerir polish de UI/animaciones como siguiente paso 1.0 sería un bug."""
    p = system_prompt_fijo()
    assert "post-1.0" in p.lower()
    # El checklist lo cita explícito; el prompt debe respaldarlo.
    assert "polish" in p.lower() or "animacion" in p.lower() \
        or "animación" in p.lower()


# ── Tool obtener_cambios_recientes registrada y testeable ──────────────────


def test_tool_obtener_cambios_recientes_registrada():
    nombres = {t["function"]["name"] for t in TOOL_DEFINITIONS}
    assert "obtener_cambios_recientes" in nombres
    # Solo lectura: no afecta tablas del hub.
    assert TABLAS_AFECTADAS["obtener_cambios_recientes"] == []


def test_parsear_git_log_separa_sha_fecha_mensaje():
    salida = (
        "aa27932\x1f2026-06-05T18:00:00-05:00\x1ffeat(wakeword): multi-window\n"
        "c927b97\x1f2026-06-05T15:00:00-05:00\x1ffeat(horario): practica\n"
    )
    out = parsear_git_log(salida)
    assert len(out) == 2
    assert out[0] == {
        "sha": "aa27932",
        "fecha": "2026-06-05T18:00:00-05:00",
        "mensaje": "feat(wakeword): multi-window",
    }
    assert out[1]["sha"] == "c927b97"


def test_parsear_git_log_tolera_lineas_vacias_y_campos_faltantes():
    assert parsear_git_log("") == []
    assert parsear_git_log("\n\n") == []
    fragil = parsear_git_log("abc123\x1f2026-01-01T00:00:00Z")
    assert fragil == [{"sha": "abc123", "fecha": "2026-01-01T00:00:00Z", "mensaje": ""}]


@pytest.mark.asyncio
async def test_obtener_cambios_recientes_devuelve_commits_reales(tmp_path):
    """Corre git log de verdad sobre el repo (tests viven dentro del repo)."""
    res = await ejecutar_tool(None, "obtener_cambios_recientes", {"n": 5})
    assert res["ok"] is True
    commits = res["datos"]["commits"]
    # En entornos sin git, devuelve [] con motivo honesto (no rompe).
    if not commits:
        assert "motivo" in res["datos"]
        return
    assert 1 <= len(commits) <= 5
    for c in commits:
        assert c["sha"]  # hash corto presente
        assert "T" in c["fecha"]  # ISO 8601
        assert c["mensaje"]


@pytest.mark.asyncio
async def test_obtener_cambios_recientes_clampa_n():
    """n fuera de [1, 50] se acota; default 10."""
    # n grande: se acota a 50 (no revienta).
    r = await ejecutar_tool(None, "obtener_cambios_recientes", {"n": 9999})
    assert r["ok"] is True
    if r["datos"]["commits"]:
        assert len(r["datos"]["commits"]) <= 50
    # n nulo: cae al default 10.
    r2 = await ejecutar_tool(None, "obtener_cambios_recientes", {})
    assert r2["ok"] is True
