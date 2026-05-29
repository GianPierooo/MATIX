"""Tests del endpoint de captura rápida desde Inicio (Capa 3 Paso C2).

`POST /matix/capturar-apunte` recibe un texto (ya transcrito por
Whisper) y lo guarda como apunte ya clasificado, en una sola pasada:
fuerza la tool `crear_apunte` (Paso C) sin abrir conversación.

No pegamos al modelo real (no-determinista y caro): monkeypatcheamos
`llm.responder_con_tools` para simular qué tool_call decide el modelo.
La ejecución de la tool SÍ es real (crea el apunte en Supabase e
indexa por el RAG igual que en producción), así validamos que el
endpoint traduce el resultado a la respuesta estructurada que la app
usa para el snackbar y el "abrir/corregir".
"""
from __future__ import annotations

import pytest
from httpx import AsyncClient

from app.matix import llm


def _tool_call_crear_apunte(args: dict) -> dict:
    """Respuesta pre-armada del modelo: una sola llamada a
    `crear_apunte` con `args`. `raw` es un dict mínimo — el endpoint
    no lo re-inyecta (la captura no tiene loop)."""
    return {
        "tipo": "tool_calls",
        "tool_calls": [
            {"id": "call_capt_1", "nombre": "crear_apunte", "args": args}
        ],
        "raw": {
            "role": "assistant",
            "tool_calls": [
                {
                    "id": "call_capt_1",
                    "type": "function",
                    "function": {
                        "name": "crear_apunte",
                        "arguments": "{}",
                    },
                }
            ],
        },
    }


async def test_capturar_apunte_general(
    client: AsyncClient, monkeypatch
):
    """Idea suelta → apunte general. La respuesta trae id, titulo,
    general=True y tablas_cambiadas=['apuntes']."""

    async def fake(messages, tools, **kw):
        # El endpoint fuerza la tool: debe pasarse tool_choice.
        assert kw.get("tool_choice") is not None
        return _tool_call_crear_apunte(
            {
                "titulo": "_test_capt_general",
                "contenido": "una idea suelta dictada desde inicio",
            }
        )

    monkeypatch.setattr(llm, "responder_con_tools", fake)

    r = await client.post(
        "/api/v1/matix/capturar-apunte",
        json={"texto": "anota que tengo una idea suelta"},
    )
    assert r.status_code == 200, r.text
    data = r.json()
    aid = data["id"]
    try:
        assert data["titulo"] == "_test_capt_general"
        assert data["general"] is True
        assert data["proyecto_nombre"] is None
        assert data["curso_nombre"] is None
        assert data["tablas_cambiadas"] == ["apuntes"]
        # El apunte quedó realmente en BD.
        got = (await client.get(f"/api/v1/apuntes/{aid}")).json()
        assert got["titulo"] == "_test_capt_general"
    finally:
        await client.delete(f"/api/v1/apuntes/{aid}/permanente")


async def test_capturar_apunte_clasificado_a_proyecto(
    client: AsyncClient, monkeypatch
):
    """Si el modelo etiqueta a un proyecto existente, la respuesta
    reporta el nombre del proyecto y general=False."""
    crear = await client.post(
        "/api/v1/proyectos",
        json={"nombre": "_test_capt_proyecto", "estado": "aparcado"},
    )
    assert crear.status_code == 201, crear.text
    pid = crear.json()["id"]

    async def fake(messages, tools, **kw):
        return _tool_call_crear_apunte(
            {
                "titulo": "_test_capt_clasif",
                "contenido": "idea que pertenece al proyecto",
                "proyecto_id": pid,
            }
        )

    monkeypatch.setattr(llm, "responder_con_tools", fake)

    r = await client.post(
        "/api/v1/matix/capturar-apunte",
        json={"texto": "anota esto para el proyecto"},
    )
    assert r.status_code == 200, r.text
    data = r.json()
    aid = data["id"]
    try:
        assert data["general"] is False
        assert data["proyecto_nombre"] == "_test_capt_proyecto"
        assert data["curso_nombre"] is None
    finally:
        await client.delete(f"/api/v1/apuntes/{aid}/permanente")
        await client.delete(f"/api/v1/proyectos/{pid}")


async def test_capturar_apunte_texto_vacio_es_422(client: AsyncClient):
    """`texto` vacío → 422 de Pydantic. No se llama al modelo ni se
    crea apunte huérfano."""
    r = await client.post(
        "/api/v1/matix/capturar-apunte",
        json={"texto": ""},
    )
    assert r.status_code == 422


async def test_capturar_apunte_modelo_no_llama_tool_es_503(
    client: AsyncClient, monkeypatch
):
    """Forzamos la tool, así que el modelo NO debería responder texto.
    Si igual lo hace, `capturar_apunte` levanta RuntimeError y el
    endpoint responde 503 — el error se ve, no muere en silencio."""

    async def fake(messages, tools, **kw):
        return {
            "tipo": "texto",
            "contenido": "no guardé nada",
            "raw": {"role": "assistant", "content": "no guardé nada"},
        }

    monkeypatch.setattr(llm, "responder_con_tools", fake)

    r = await client.post(
        "/api/v1/matix/capturar-apunte",
        json={"texto": "algo que debería guardarse"},
    )
    assert r.status_code == 503


async def test_capturar_apunte_requiere_api_key(client_anon: AsyncClient):
    """Sin `X-Matix-Key` → 401, como el resto de `/matix`."""
    r = await client_anon.post(
        "/api/v1/matix/capturar-apunte",
        json={"texto": "hola"},
    )
    assert r.status_code == 401
