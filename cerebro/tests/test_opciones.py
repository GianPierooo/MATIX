"""Opciones tocables (preguntar_con_opciones): handler + integración en chat."""
from __future__ import annotations

from app.matix import chat as chat_mod
from app.matix import tools


# ── Handler (puro) ──────────────────────────────────────────────────
async def test_handler_seleccion_unica_ok():
    r = await tools._preguntar_con_opciones(
        None,
        {"pregunta": "¿Qué modo activo?", "tipo": "seleccion_unica",
         "opciones": ["Tesis", "Estudio", "Finanzas"]},
    )
    assert r["ok"]
    d = r["datos"]
    assert d["pregunta"] == "¿Qué modo activo?"
    assert d["tipo"] == "seleccion_unica"
    assert d["opciones"] == ["Tesis", "Estudio", "Finanzas"]
    # Regla de oro: el texto libre va activado por defecto.
    assert d["permite_texto"] is True


async def test_handler_permite_texto_se_puede_apagar():
    r = await tools._preguntar_con_opciones(
        None,
        {"pregunta": "¿sí o no?", "tipo": "seleccion_unica",
         "opciones": ["sí", "no"], "permite_texto": False},
    )
    assert r["ok"] and r["datos"]["permite_texto"] is False


async def test_handler_texto_sin_opciones_ok():
    r = await tools._preguntar_con_opciones(
        None, {"pregunta": "¿Cómo se llama tu tesis?", "tipo": "texto"}
    )
    assert r["ok"] and r["datos"]["tipo"] == "texto"
    assert r["datos"]["opciones"] == []


async def test_handler_seleccion_con_una_opcion_falla():
    r = await tools._preguntar_con_opciones(
        None, {"pregunta": "x", "tipo": "seleccion_unica", "opciones": ["A"]}
    )
    assert not r["ok"]


async def test_handler_tipo_invalido_falla():
    r = await tools._preguntar_con_opciones(
        None, {"pregunta": "x", "tipo": "ranking", "opciones": ["A", "B"]}
    )
    assert not r["ok"]


# ── Integración en conversar ────────────────────────────────────────
async def _sin(db):
    return ""


async def _sin_modo(db):
    return None


async def test_conversar_emite_bloque_y_termina_turno(monkeypatch):
    llamadas = {"n": 0}

    async def fake(messages, tools_defs, *, model=None, temperature=0.6, tool_choice="auto"):
        llamadas["n"] += 1
        # Matix pide opciones (una sola vuelta: el turno debe terminar acá).
        return {
            "tipo": "tool_calls",
            "tool_calls": [
                {
                    "id": "c1",
                    "nombre": "preguntar_con_opciones",
                    "args": {
                        "pregunta": "¿Qué plazo?",
                        "tipo": "seleccion_unica",
                        "opciones": ["Corto", "Medio", "Largo"],
                    },
                }
            ],
            "raw": {"role": "assistant", "content": "", "tool_calls": []},
        }

    monkeypatch.setattr(chat_mod.llm, "responder_con_tools", fake)
    monkeypatch.setattr(chat_mod, "contexto_vivo", _sin)
    monkeypatch.setattr(chat_mod.memoria, "bloque_memoria", _sin)
    monkeypatch.setattr(chat_mod.modos, "modo_activo", _sin_modo)

    async def sel(db):
        return "gpt-4o-mini"

    monkeypatch.setattr(chat_mod.modelos_llm, "seleccion_guardada", sel)

    r = await chat_mod.conversar(None, historial=[], mensaje="ayúdame a planear")
    # El turno terminó tras una vuelta (no se re-invocó al modelo).
    assert llamadas["n"] == 1
    # La pregunta es el mensaje visible y el bloque viaja aparte.
    assert r["respuesta"] == "¿Qué plazo?"
    assert r["opciones"] is not None
    assert r["opciones"]["tipo"] == "seleccion_unica"
    assert r["opciones"]["opciones"] == ["Corto", "Medio", "Largo"]


async def test_conversar_sin_opciones_es_none(monkeypatch):
    async def fake(messages, tools_defs, *, model=None, temperature=0.6, tool_choice="auto"):
        return {"tipo": "texto", "contenido": "hola", "raw": {"role": "assistant", "content": "hola"}}

    monkeypatch.setattr(chat_mod.llm, "responder_con_tools", fake)
    monkeypatch.setattr(chat_mod, "contexto_vivo", _sin)
    monkeypatch.setattr(chat_mod.memoria, "bloque_memoria", _sin)
    monkeypatch.setattr(chat_mod.modos, "modo_activo", _sin_modo)

    async def sel(db):
        return "gpt-4o-mini"

    monkeypatch.setattr(chat_mod.modelos_llm, "seleccion_guardada", sel)

    r = await chat_mod.conversar(None, historial=[], mensaje="hola")
    assert r["opciones"] is None
