"""Chat: selección de modelo + continuidad al cambiar de proveedor.

CRÍTICO: al cambiar de modelo (y por ende de proveedor) a mitad de
conversación, el historial se reconstruye desde los campos NEUTROS
({rol, contenido} de texto) para el proveedor del turno; nunca se reusa el
`raw` (formato nativo) de un turno de otro proveedor. Y el modelo se resuelve
UNA vez por turno (mismo proveedor en todas las vueltas del loop).

No pegamos al modelo ni a la BD: mockeamos `responder_con_tools`, el contexto,
la memoria, los modos y la selección de modelo.
"""
from __future__ import annotations

from app.matix import chat as chat_mod


async def _sin_contexto(db):
    return ""


async def _sin_memoria(db):
    return ""


async def _sin_modo(db):
    return None


def _bloques_tool_use(messages):
    """¿Algún mensaje trae bloques `raw` (tool_use) de otro proveedor?"""
    for m in messages:
        c = m.get("content")
        if isinstance(c, list) and c and isinstance(c[0], dict) and c[0].get("type") == "tool_use":
            return True
    return False


async def test_modelo_seleccionado_y_continuidad_al_cambiar_proveedor(monkeypatch):
    capturas: list[dict] = []

    async def fake_resp(messages, tools, *, model=None, temperature=0.6, tool_choice="auto"):
        capturas.append({"model": model, "messages": list(messages)})
        return {"tipo": "texto", "contenido": "ok", "raw": {"role": "assistant", "content": "ok"}}

    monkeypatch.setattr(chat_mod.llm, "responder_con_tools", fake_resp)
    monkeypatch.setattr(chat_mod, "contexto_vivo", _sin_contexto)
    monkeypatch.setattr(chat_mod.memoria, "bloque_memoria", _sin_memoria)
    monkeypatch.setattr(chat_mod.modos, "modo_activo", _sin_modo)

    historial = [
        {"rol": "user", "contenido": "hola"},
        {"rol": "assistant", "contenido": "hey, dime"},
    ]

    # Turno 1: modelo OpenAI.
    async def sel_oai(db):
        return "gpt-4o-mini"

    monkeypatch.setattr(chat_mod.modelos_llm, "seleccion_guardada", sel_oai)
    r1 = await chat_mod.conversar(None, historial=historial, mensaje="¿qué tal?")
    assert r1["respuesta"] == "ok"
    # Pasó el modelo seleccionado a responder_con_tools.
    assert capturas[-1]["model"] == "gpt-4o-mini"
    assert r1["modelo_usado"] == "gpt-4o-mini" and r1["auto"] is False
    # El historial se reconstruyó desde el texto neutro.
    contenidos = [m["content"] for m in capturas[-1]["messages"] if m.get("role") in ("user", "assistant")]
    assert "hola" in contenidos and "hey, dime" in contenidos
    assert not _bloques_tool_use(capturas[-1]["messages"])

    # Turno 2: el usuario cambió a un modelo Anthropic. Mismo historial neutro.
    async def sel_anth(db):
        return "claude-opus-4-8"

    monkeypatch.setattr(chat_mod.modelos_llm, "seleccion_guardada", sel_anth)
    r2 = await chat_mod.conversar(None, historial=historial, mensaje="sigue")
    assert r2["respuesta"] == "ok"
    assert capturas[-1]["model"] == "claude-opus-4-8"
    # Se reconstruyó otra vez desde los neutros — sin raw del turno anterior.
    contenidos2 = [m["content"] for m in capturas[-1]["messages"] if m.get("role") in ("user", "assistant")]
    assert "hola" in contenidos2
    assert not _bloques_tool_use(capturas[-1]["messages"])


async def test_auto_rutea_por_mensaje(monkeypatch):
    """En modo Automático, el modelo lo elige el enrutador SEGÚN el mensaje:
    barato para un comando corto, fuerte para razonamiento. Y el turno
    reporta `auto=True` con el modelo que realmente respondió."""
    capturas: list[dict] = []

    async def fake_resp(messages, tools, *, model=None, temperature=0.6, tool_choice="auto"):
        capturas.append({"model": model})
        return {"tipo": "texto", "contenido": "ok", "raw": {"role": "assistant", "content": "ok"}}

    monkeypatch.setattr(chat_mod.llm, "responder_con_tools", fake_resp)
    monkeypatch.setattr(chat_mod, "contexto_vivo", _sin_contexto)
    monkeypatch.setattr(chat_mod.memoria, "bloque_memoria", _sin_memoria)
    monkeypatch.setattr(chat_mod.modos, "modo_activo", _sin_modo)

    async def sel_auto(db):
        return chat_mod.modelos_llm.AUTO

    async def par(db):
        return ("gpt-4o-mini", "claude-sonnet-4-6")

    monkeypatch.setattr(chat_mod.modelos_llm, "seleccion_guardada", sel_auto)
    monkeypatch.setattr(chat_mod.modelos_llm, "par_barato_fuerte", par)

    # Comando corto → barato. Usamos «qué tengo hoy?» (pregunta corta) para
    # que NO lo intercepte el clasificador rápido pre-LLM (que come "crea
    # tarea X" sin fecha y similares): aquí queremos validar el ruteo del
    # MODELO en el camino LLM, no el atajo.
    r1 = await chat_mod.conversar(None, historial=[], mensaje="qué tengo hoy?")
    assert r1["auto"] is True
    assert r1["modelo_usado"] == "gpt-4o-mini"
    assert capturas[-1]["model"] == "gpt-4o-mini"

    # Razonamiento/escritura a fondo → fuerte.
    r2 = await chat_mod.conversar(
        None, historial=[], mensaje="analiza a fondo y compara estas dos teorías"
    )
    assert r2["auto"] is True
    assert r2["modelo_usado"] == "claude-sonnet-4-6"
    assert capturas[-1]["model"] == "claude-sonnet-4-6"


async def test_varias_imagenes_en_un_mensaje(monkeypatch):
    """Un mensaje con VARIAS imágenes arma un content multimodal con un bloque
    por imagen (texto + N imágenes), las capa a 5, y en auto rutea a fuerte."""
    capturas: list[dict] = []

    async def fake_resp(messages, tools, *, model=None, temperature=0.6, tool_choice="auto"):
        capturas.append({"model": model, "messages": list(messages)})
        return {"tipo": "texto", "contenido": "ok", "raw": {"role": "assistant", "content": "ok"}}

    monkeypatch.setattr(chat_mod.llm, "responder_con_tools", fake_resp)
    monkeypatch.setattr(chat_mod, "contexto_vivo", _sin_contexto)
    monkeypatch.setattr(chat_mod.memoria, "bloque_memoria", _sin_memoria)
    monkeypatch.setattr(chat_mod.modos, "modo_activo", _sin_modo)

    async def sel_auto(db):
        return chat_mod.modelos_llm.AUTO

    async def par(db):
        return ("gpt-4o-mini", "claude-sonnet-4-6")

    monkeypatch.setattr(chat_mod.modelos_llm, "seleccion_guardada", sel_auto)
    monkeypatch.setattr(chat_mod.modelos_llm, "par_barato_fuerte", par)

    imgs = [f"data:image/jpeg;base64,img{i}" for i in range(7)]  # 7 → cap a 5
    r = await chat_mod.conversar(None, historial=[], mensaje="mira estas", imagenes=imgs)

    # El último mensaje (user) trae texto + un bloque de imagen por cada una.
    user_msg = capturas[-1]["messages"][-1]
    assert user_msg["role"] == "user"
    bloques = user_msg["content"]
    imgs_blocks = [b for b in bloques if b.get("type") == "image_url"]
    assert len(imgs_blocks) == 5  # capadas a _MAX_IMAGENES
    assert bloques[0]["type"] == "text"
    # Con imágenes, en auto va al modelo fuerte (mejor lectura).
    assert r["modelo_usado"] == "claude-sonnet-4-6"


async def test_imagen_singular_sigue_funcionando(monkeypatch):
    """Back-compat: el viejo `imagen` (una sola) sigue armando un bloque."""
    capturas: list[dict] = []

    async def fake_resp(messages, tools, *, model=None, temperature=0.6, tool_choice="auto"):
        capturas.append(list(messages))
        return {"tipo": "texto", "contenido": "ok", "raw": {"role": "assistant", "content": "ok"}}

    monkeypatch.setattr(chat_mod.llm, "responder_con_tools", fake_resp)
    monkeypatch.setattr(chat_mod, "contexto_vivo", _sin_contexto)
    monkeypatch.setattr(chat_mod.memoria, "bloque_memoria", _sin_memoria)
    monkeypatch.setattr(chat_mod.modos, "modo_activo", _sin_modo)

    async def sel(db):
        return "gpt-4o-mini"

    monkeypatch.setattr(chat_mod.modelos_llm, "seleccion_guardada", sel)

    await chat_mod.conversar(
        None, historial=[], mensaje="qué ves", imagen="data:image/jpeg;base64,uno"
    )
    user_msg = capturas[-1][-1]
    imgs_blocks = [b for b in user_msg["content"] if b.get("type") == "image_url"]
    assert len(imgs_blocks) == 1


async def test_documento_adjunto_se_inyecta_y_rutea_a_fuerte(monkeypatch):
    """Un documento adjunto entra como contexto `system` del turno y, en
    Automático, fuerza el modelo fuerte aunque el mensaje sea corto."""
    capturas: list[dict] = []

    async def fake_resp(messages, tools, *, model=None, temperature=0.6, tool_choice="auto"):
        capturas.append({"model": model, "messages": list(messages)})
        return {"tipo": "texto", "contenido": "ok", "raw": {"role": "assistant", "content": "ok"}}

    monkeypatch.setattr(chat_mod.llm, "responder_con_tools", fake_resp)
    monkeypatch.setattr(chat_mod, "contexto_vivo", _sin_contexto)
    monkeypatch.setattr(chat_mod.memoria, "bloque_memoria", _sin_memoria)
    monkeypatch.setattr(chat_mod.modos, "modo_activo", _sin_modo)

    async def sel_auto(db):
        return chat_mod.modelos_llm.AUTO

    async def par(db):
        return ("gpt-4o-mini", "claude-sonnet-4-6")

    monkeypatch.setattr(chat_mod.modelos_llm, "seleccion_guardada", sel_auto)
    monkeypatch.setattr(chat_mod.modelos_llm, "par_barato_fuerte", par)

    r = await chat_mod.conversar(
        None,
        historial=[],
        mensaje="resúmelo",  # corto: sin documento iría a barato
        documento={"nombre": "silabo.pdf", "texto": "TEMARIO DEL CURSO XYZ"},
    )
    assert r["auto"] is True
    assert r["modelo_usado"] == "claude-sonnet-4-6"
    blob = "\n".join(
        m["content"] for m in capturas[-1]["messages"] if isinstance(m.get("content"), str)
    )
    assert "DOCUMENTO ADJUNTO" in blob and "silabo.pdf" in blob
    assert "TEMARIO DEL CURSO XYZ" in blob
