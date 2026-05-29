"""Tests del endpoint texto OCR → tareas propuestas (Capa 7-B).

`POST /matix/extraer-tareas` recibe el texto que la app extrajo de una
foto (Capa 7-A) y ya corrigió el usuario, y devuelve tareas
estructuradas para que el usuario las revise y confirme. NO persiste
nada: la app crea las tareas con su CRUD tras la confirmación.

No pegamos al modelo real (no-determinista y caro): monkeypatcheamos
`llm.extraer_tareas_json` para fijar qué devuelve. Validamos que el
endpoint serializa bien la respuesta (fechas, título, lista vacía) y
que respeta la autenticación.
"""
from __future__ import annotations

from httpx import AsyncClient

from app.matix import llm


async def test_extraer_tareas_con_fecha_y_sin_fecha(
    client: AsyncClient, monkeypatch
):
    """Dos tareas: una con fecha resuelta, otra sin fecha. La respuesta
    conserva el orden, la fecha como YYYY-MM-DD y el null como null."""

    async def fake(texto, *, hoy, **kw):
        # El router pasa la fecha de hoy en Lima como referencia.
        assert isinstance(hoy, str) and len(hoy) == 10
        return [
            {"titulo": "Comprar pan", "vence_en": "2026-05-30"},
            {"titulo": "Llamar a Ana", "vence_en": None},
        ]

    monkeypatch.setattr(llm, "extraer_tareas_json", fake)

    r = await client.post(
        "/api/v1/matix/extraer-tareas",
        json={"texto": "comprar pan el viernes\nllamar a ana"},
    )
    assert r.status_code == 200, r.text
    tareas = r.json()["tareas"]
    assert tareas == [
        {"titulo": "Comprar pan", "vence_en": "2026-05-30"},
        {"titulo": "Llamar a Ana", "vence_en": None},
    ]


async def test_extraer_tareas_sin_tareas_devuelve_lista_vacia(
    client: AsyncClient, monkeypatch
):
    """Texto sin acciones claras → lista vacía. Es un resultado válido,
    no un error: status 200 con tareas=[]."""

    async def fake(texto, *, hoy, **kw):
        return []

    monkeypatch.setattr(llm, "extraer_tareas_json", fake)

    r = await client.post(
        "/api/v1/matix/extraer-tareas",
        json={"texto": "La fotosíntesis es el proceso por el cual..."},
    )
    assert r.status_code == 200, r.text
    assert r.json()["tareas"] == []


async def test_extraer_tareas_texto_vacio_es_422(client: AsyncClient):
    """`texto` vacío → 422 de Pydantic. Ni se llama al modelo."""
    r = await client.post(
        "/api/v1/matix/extraer-tareas",
        json={"texto": ""},
    )
    assert r.status_code == 422


async def test_extraer_tareas_modelo_falla_es_502(
    client: AsyncClient, monkeypatch
):
    """Si el modelo revienta, el error se ve como 502 — no muere en
    silencio. La app muestra mensaje claro + reintento."""

    async def fake(texto, *, hoy, **kw):
        raise Exception("boom")

    monkeypatch.setattr(llm, "extraer_tareas_json", fake)

    r = await client.post(
        "/api/v1/matix/extraer-tareas",
        json={"texto": "algo"},
    )
    assert r.status_code == 502


async def test_extraer_tareas_requiere_api_key(client_anon: AsyncClient):
    """Sin `X-Matix-Key` → 401, como el resto de `/matix`."""
    r = await client_anon.post(
        "/api/v1/matix/extraer-tareas",
        json={"texto": "hola"},
    )
    assert r.status_code == 401
