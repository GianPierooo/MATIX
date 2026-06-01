"""Estado de Matix + reporte del modelo real + historial entre proveedores.

- El bloque ESTADO DE MATIX inyecta el modelo REAL del turno (id + nombre).
- En Automático reporta el modelo RESUELTO para ese mensaje.
- El historial sobrevive al cambio de proveedor, incluso con un turno
  solo-imagen (texto vacío) que Anthropic rechazaría sin el placeholder.
"""
from __future__ import annotations

from app.matix import chat as chat_mod
from app.matix import estado, llm


# ── Estado (puro) ───────────────────────────────────────────────────
def test_bloque_estado_reporta_modelo_fijo():
    b = estado.bloque_estado(
        modelo_id="claude-sonnet-4-6",
        modelo_etiqueta="Claude Sonnet 4.6",
        auto=False,
    )
    assert "Claude Sonnet 4.6" in b
    assert "claude-sonnet-4-6" in b
    # La nota específica del modo Automático no aparece con modelo fijo
    # (el changelog sí menciona la palabra, por eso chequeamos la frase).
    assert "estás en Automático" not in b
    assert estado.VERSION in b


def test_bloque_estado_en_auto_menciona_automatico():
    b = estado.bloque_estado(
        modelo_id="gpt-4o-mini", modelo_etiqueta="GPT-4o mini", auto=True
    )
    assert "Automático" in b
    assert "GPT-4o mini" in b


# ── Anthropic nunca recibe contenido vacío ──────────────────────────
def test_contenido_usuario_anthropic_no_vacio():
    assert llm._contenido_usuario_anthropic("") == "(adjunto)"
    assert llm._contenido_usuario_anthropic("hola") == "hola"
    # Lista con solo texto vacío → placeholder, no lista vacía.
    assert llm._contenido_usuario_anthropic([{"type": "text", "text": "  "}]) == "(adjunto)"


# ── conversar: modelo reportado + historial cross-provider ──────────
async def _sin(db):
    return ""


async def _sin_modo(db):
    return None


async def test_conversar_inyecta_modelo_real(monkeypatch):
    cap: list[dict] = []

    async def fake(messages, tools, *, model=None, temperature=0.6, tool_choice="auto"):
        cap.append({"model": model, "messages": list(messages)})
        return {"tipo": "texto", "contenido": "ok", "raw": {"role": "assistant", "content": "ok"}}

    monkeypatch.setattr(chat_mod.llm, "responder_con_tools", fake)
    monkeypatch.setattr(chat_mod, "contexto_vivo", _sin)
    monkeypatch.setattr(chat_mod.memoria, "bloque_memoria", _sin)
    monkeypatch.setattr(chat_mod.modos, "modo_activo", _sin_modo)

    async def sel(db):
        return "claude-sonnet-4-6"

    monkeypatch.setattr(chat_mod.modelos_llm, "seleccion_guardada", sel)

    r = await chat_mod.conversar(None, historial=[], mensaje="¿en qué modelo estás?")
    assert r["modelo_usado"] == "claude-sonnet-4-6"
    blob = "\n".join(
        m["content"] for m in cap[-1]["messages"] if isinstance(m.get("content"), str)
    )
    assert "ESTADO DE MATIX" in blob
    assert "Claude Sonnet 4.6" in blob  # nombre amigable real, no "GPT-4o"
    assert "GPT-4o" not in blob


async def test_historial_sobrevive_cambio_de_proveedor_con_turno_vacio(monkeypatch):
    cap: list[dict] = []

    async def fake(messages, tools, *, model=None, temperature=0.6, tool_choice="auto"):
        cap.append({"model": model, "messages": list(messages)})
        return {"tipo": "texto", "contenido": "ok", "raw": {"role": "assistant", "content": "ok"}}

    monkeypatch.setattr(chat_mod.llm, "responder_con_tools", fake)
    monkeypatch.setattr(chat_mod, "contexto_vivo", _sin)
    monkeypatch.setattr(chat_mod.memoria, "bloque_memoria", _sin)
    monkeypatch.setattr(chat_mod.modos, "modo_activo", _sin_modo)

    # Historial real: incluye un turno de usuario solo-imagen (contenido vacío).
    historial = [
        {"rol": "user", "contenido": "hola"},
        {"rol": "assistant", "contenido": "hey, dime"},
        {"rol": "user", "contenido": ""},          # solo imagen
        {"rol": "assistant", "contenido": "veo la foto"},
    ]

    # Turno 1 en OpenAI.
    async def sel_oai(db):
        return "gpt-4o-mini"

    monkeypatch.setattr(chat_mod.modelos_llm, "seleccion_guardada", sel_oai)
    await chat_mod.conversar(None, historial=historial, mensaje="sigue")
    msgs1 = [m for m in cap[-1]["messages"] if m.get("role") in ("user", "assistant")]
    textos1 = [m["content"] for m in msgs1]
    assert "hola" in textos1 and "veo la foto" in textos1
    assert "" not in textos1  # el turno vacío quedó con placeholder
    assert "(adjunto)" in textos1

    # Turno 2: cambia a Claude. Mismo historial neutro; no debe romperse.
    async def sel_anth(db):
        return "claude-opus-4-8"

    monkeypatch.setattr(chat_mod.modelos_llm, "seleccion_guardada", sel_anth)
    r2 = await chat_mod.conversar(None, historial=historial, mensaje="y ahora en Claude")
    assert r2["respuesta"] == "ok"
    assert cap[-1]["model"] == "claude-opus-4-8"
    textos2 = [m["content"] for m in cap[-1]["messages"] if m.get("role") in ("user", "assistant")]
    assert "hola" in textos2  # historial intacto tras cambiar de proveedor
    assert "" not in textos2
