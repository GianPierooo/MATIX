"""Tres bugs reportados en "Tu día":

  1. Agregar no funciona (Flutter — testeo el lado cerebro: clasifica y devuelve
     el envelope correcto).
  2. Sugerencias creadas como Evento cuando deberían ser Tarea.
  3. Sugerencias conscientes de la hora — no proponer "hoy 20:10" si ya es de
     noche según TU ancla de dormir.
"""
from __future__ import annotations

import json
from unittest.mock import AsyncMock

import pytest

from app.matix import chat, horario


# ── Bug #3: ventana útil restante respeta el ancla de dormir + buffer ────────


def test_ventanas_libres_resta_buffer_pre_sueno():
    """Si duermes a las 23 y faltan 60 min de buffer, el día útil termina 22:00.
    A las 21:00 con tarea de 20 min: hay ventana de 60 min (21:00-22:00), no
    de 120 min (que sería pegada al sueño)."""
    ventanas = horario.ventanas_libres(
        [], despertar_min=7 * 60, dormir_min=23 * 60,
        buffer_min=10, desde_min=21 * 60, buffer_pre_sueno_min=60,
    )
    assert len(ventanas) == 1
    assert ventanas[0]["ini"] == 21 * 60
    assert ventanas[0]["fin"] == 22 * 60  # 23:00 - 60min buffer
    assert ventanas[0]["dur"] == 60


def test_ventanas_libres_ya_es_tarde_no_propone_hoy():
    """Caso del bug: dormir 23, ahora 22:30, buffer 60 → ventana útil termina
    22:00, que ya pasó. NO se ofrecen ventanas para HOY."""
    ventanas = horario.ventanas_libres(
        [], despertar_min=7 * 60, dormir_min=23 * 60,
        buffer_min=10, desde_min=22 * 60 + 30, buffer_pre_sueno_min=60,
    )
    assert ventanas == []


def test_ventanas_libres_buffer_pequeno_aun_propone_hoy():
    """Si quedan 3h y la tarea cabe (con buffer), debe ofrecer hoy."""
    ventanas = horario.ventanas_libres(
        [], despertar_min=7 * 60, dormir_min=23 * 60,
        buffer_min=10, desde_min=19 * 60, buffer_pre_sueno_min=60,
    )
    assert len(ventanas) == 1
    assert ventanas[0]["fin"] == 22 * 60
    assert ventanas[0]["dur"] == 180  # 3h


def test_ventanas_libres_buffer_cero_compat_legacy():
    """Sin buffer pre-sueño, el comportamiento es el de antes: hasta dormir."""
    ventanas = horario.ventanas_libres(
        [], despertar_min=7 * 60, dormir_min=23 * 60,
        buffer_min=10, desde_min=20 * 60,
    )
    assert len(ventanas) == 1
    assert ventanas[0]["fin"] == 23 * 60


def test_ventanas_libres_ancla_dormir_temprana_no_propone_tarde():
    """Si tu ancla de dormir es 21:00 (no 23:00), a las 19:30 con buffer 60
    el día útil ya cerró (20:00 - 60min = ya pasó)."""
    ventanas = horario.ventanas_libres(
        [], despertar_min=7 * 60, dormir_min=21 * 60,
        buffer_min=10, desde_min=19 * 60 + 30, buffer_pre_sueno_min=60,
    )
    # 21:00 - 60 = 20:00 utilidad, desde 19:30 → ventana de 30 min
    assert len(ventanas) == 1
    assert ventanas[0]["dur"] == 30


# ── Bug #2: la captura rápida NUNCA crea evento ──────────────────────────────


def test_captura_no_expone_crear_evento():
    """Whitelist explícita: la captura rápida solo ve `crear_tarea` y
    `crear_apunte`. El modelo no puede llamar a `crear_evento` desde aquí."""
    tools = chat._tools_para_captura()
    nombres = {t["function"]["name"] for t in tools}
    assert nombres == {"crear_tarea", "crear_apunte"}
    assert "crear_evento" not in nombres


async def test_captura_accion_crea_tarea(monkeypatch):
    """«Comprar pan» es una acción → la captura genera `crear_tarea`."""
    async def fake_responder(messages, tools, *, model, tool_choice, **kw):
        # Verificamos el contrato: tool_choice=required (forzamos llamar UNA).
        assert tool_choice == "required"
        return {
            "tipo": "tool_calls",
            "tool_calls": [{"id": "1", "nombre": "crear_tarea",
                            "args": {"titulo": "Comprar pan"}}],
            "raw": {},
        }
    async def fake_ejec(db, name, args, conversacion_id=None):
        return {"ok": True, "datos": {"id": "t1", "titulo": args["titulo"]}}

    monkeypatch.setattr(chat.llm, "responder_con_tools", fake_responder)
    monkeypatch.setattr(chat, "ejecutar_tool", fake_ejec)
    monkeypatch.setattr(chat, "contexto_vivo", AsyncMock(return_value=""))
    monkeypatch.setattr(chat.modelos_llm, "modelo_seleccionado",
                        AsyncMock(return_value="gpt-4o-mini"))

    resultado = await chat.capturar_apunte(db=None, texto="Comprar pan")
    assert resultado["tipo"] == "tarea"
    assert resultado["datos"]["titulo"] == "Comprar pan"


async def test_captura_idea_crea_apunte(monkeypatch):
    """«Reflexión sobre el plan» es una nota → `crear_apunte`."""
    async def fake_responder(messages, tools, *, model, tool_choice, **kw):
        return {
            "tipo": "tool_calls",
            "tool_calls": [{"id": "1", "nombre": "crear_apunte",
                            "args": {"titulo": "Reflexión", "contenido": "X"}}],
            "raw": {},
        }
    async def fake_ejec(db, name, args, conversacion_id=None):
        return {"ok": True, "datos": {"id": "a1", "titulo": args["titulo"]}}

    monkeypatch.setattr(chat.llm, "responder_con_tools", fake_responder)
    monkeypatch.setattr(chat, "ejecutar_tool", fake_ejec)
    monkeypatch.setattr(chat, "contexto_vivo", AsyncMock(return_value=""))
    monkeypatch.setattr(chat.modelos_llm, "modelo_seleccionado",
                        AsyncMock(return_value="gpt-4o-mini"))

    resultado = await chat.capturar_apunte(
        db=None, texto="Reflexión sobre cómo enfoco el día"
    )
    assert resultado["tipo"] == "apunte"


def test_descripcion_crear_evento_dice_no_inventar_hora():
    """El description que ve el modelo debe decir taxativamente: si no hay
    hora explícita, es TAREA. Anti-bug #2 desde el origen."""
    from app.matix.tools import TOOL_DEFINITIONS
    desc = next(
        t["function"]["description"] for t in TOOL_DEFINITIONS
        if t["function"]["name"] == "crear_evento"
    )
    desc_low = desc.lower()
    assert "no inventes" in desc_low or "no invent" in desc_low
    assert "tarea" in desc_low
    assert "hora" in desc_low
