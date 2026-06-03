"""Acciones de teléfono (Capa 6 · Fase 1): las tools PROPONEN un Intent que la
app ejecuta. Sin BD ni red (los handlers no tocan Supabase)."""
from __future__ import annotations

import pytest

from app.matix import tools


async def _llamar(nombre, args):
    return await tools.ejecutar_tool(None, nombre, args)


@pytest.mark.asyncio
async def test_redactar_mensaje_sms_propone_prefill():
    # SMS/correo siguen siendo prefill (tipo "mensaje"). WhatsApp NO (se prueba
    # aparte: se re-rutea al flujo seguro).
    r = await _llamar(
        "redactar_mensaje",
        {"canal": "sms", "destinatario": "999888777", "texto": "¿nos vemos?"},
    )
    assert r["ok"], r
    acc = r["datos"]["accion_dispositivo"]
    assert acc["tipo"] == "mensaje"
    assert acc["datos"]["canal"] == "sms"
    assert acc["datos"]["texto"] == "¿nos vemos?"
    assert acc["requiere_confirmacion"] is True  # ENVÍA → confirma


@pytest.mark.asyncio
async def test_redactar_mensaje_valida():
    r = await _llamar("redactar_mensaje", {"canal": "telegram", "texto": "x"})
    assert r["ok"] is False and r["tipo"] == "validacion"
    r2 = await _llamar("redactar_mensaje", {"canal": "sms", "texto": "  "})
    assert r2["ok"] is False and r2["tipo"] == "validacion"


@pytest.mark.asyncio
async def test_redactar_mensaje_whatsapp_se_rerutea_al_flujo_seguro():
    # SEGURIDAD: WhatsApp a un contacto NUNCA es tipo "mensaje" (selector);
    # se re-rutea al flujo blindado (tipo "whatsapp").
    r = await _llamar(
        "redactar_mensaje",
        {"canal": "whatsapp", "destinatario": "Natalia", "texto": "ya voy"},
    )
    assert r["ok"], r
    acc = r["datos"]["accion_dispositivo"]
    assert acc["tipo"] == "whatsapp"  # NO "mensaje"
    assert acc["datos"]["contacto"] == "Natalia" and acc["datos"]["mensaje"] == "ya voy"


@pytest.mark.asyncio
async def test_redactar_mensaje_whatsapp_sin_destinatario_aborta_sin_selector():
    r = await _llamar("redactar_mensaje", {"canal": "whatsapp", "texto": "hola"})
    assert r["ok"] is False and r["tipo"] == "validacion"


@pytest.mark.asyncio
async def test_iniciar_llamada_confirma():
    r = await _llamar("iniciar_llamada", {"numero": "999888777", "nombre": "Papá"})
    assert r["ok"]
    acc = r["datos"]["accion_dispositivo"]
    assert acc["tipo"] == "llamada" and acc["datos"]["numero"] == "999888777"
    assert acc["requiere_confirmacion"] is True
    r2 = await _llamar("iniciar_llamada", {"numero": ""})
    assert r2["ok"] is False


@pytest.mark.asyncio
async def test_crear_evento_telefono_confirma():
    r = await _llamar(
        "crear_evento_telefono",
        {"titulo": "Dentista", "inicia_en": "2026-06-10T15:00:00-05:00"},
    )
    assert r["ok"]
    acc = r["datos"]["accion_dispositivo"]
    assert acc["tipo"] == "evento" and acc["requiere_confirmacion"] is True
    r2 = await _llamar("crear_evento_telefono", {"titulo": "x"})  # sin inicia_en
    assert r2["ok"] is False


@pytest.mark.asyncio
async def test_abrir_en_telefono_no_confirma():
    r = await _llamar("abrir_en_telefono", {"objetivo": "url", "valor": "https://x.com"})
    assert r["ok"]
    acc = r["datos"]["accion_dispositivo"]
    assert acc["tipo"] == "abrir"
    assert acc["requiere_confirmacion"] is False  # abrir = bajo riesgo
    r2 = await _llamar("abrir_en_telefono", {"objetivo": "otra", "valor": "x"})
    assert r2["ok"] is False


@pytest.mark.asyncio
async def test_leer_galeria_modo():
    r = await _llamar("leer_galeria", {"modo": "ultima", "proposito": "anota los gastos"})
    assert r["ok"]
    acc = r["datos"]["accion_dispositivo"]
    assert acc["tipo"] == "galeria" and acc["datos"]["modo"] == "ultima"
    r2 = await _llamar("leer_galeria", {"modo": "raro"})
    assert r2["ok"] is False


@pytest.mark.asyncio
async def test_leer_pantalla_solo_lectura():
    # Tier C.0: percepción. Propone leer la pantalla, sin confirmación (solo
    # lectura) y con un propósito por defecto si no se pasa.
    r = await _llamar("leer_pantalla", {"proposito": "léeme el último mensaje"})
    assert r["ok"], r
    acc = r["datos"]["accion_dispositivo"]
    assert acc["tipo"] == "pantalla"
    assert acc["datos"]["proposito"] == "léeme el último mensaje"
    assert acc["requiere_confirmacion"] is False
    # Sin propósito: usa uno por defecto, no falla.
    r2 = await _llamar("leer_pantalla", {})
    assert r2["ok"] and r2["datos"]["accion_dispositivo"]["datos"]["proposito"]


def test_tools_de_dispositivo_sincronizadas():
    defs = {t["function"]["name"] for t in tools.TOOL_DEFINITIONS}
    esperadas = {
        "redactar_mensaje", "iniciar_llamada", "crear_evento_telefono",
        "abrir_en_telefono", "leer_galeria", "leer_pantalla",
    }
    assert esperadas <= defs
    assert esperadas <= set(tools._HANDLERS)
    assert esperadas <= set(tools.TABLAS_AFECTADAS)
    assert defs == set(tools._HANDLERS) == set(tools.TABLAS_AFECTADAS)
