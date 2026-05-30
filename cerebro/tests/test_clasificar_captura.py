"""Tests del endpoint texto OCR → tipo de captura (Cámara inteligente).

`POST /matix/clasificar-captura` recibe el texto que la app extrajo de
una foto (OCR on-device) y devuelve a cuál de los tres flujos pertenece:
`tareas`, `eventos` o `apunte`. NO persiste nada — la app abre la
revisión del flujo sugerido y el usuario puede corregir el tipo.

No pegamos al modelo real (no-determinista y caro): monkeypatcheamos
`llm.clasificar_captura_json` para fijar qué devuelve. Validamos que el
endpoint serializa cada tipo, que respeta la autenticación y que rechaza
el texto vacío.
"""
from __future__ import annotations

import pytest
from httpx import AsyncClient

from app.matix import llm


@pytest.mark.parametrize(
    ("tipo", "texto"),
    [
        ("tareas", "comprar pan\nllamar a Ana\nentregar informe"),
        ("eventos", "Cálculo III lun y mié 10-12. Parcial 15 abril."),
        ("apunte", "la mitocondria es la central energética de la célula"),
    ],
)
async def test_clasifica_cada_tipo(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch, tipo: str, texto: str
) -> None:
    """Cada uno de los tres destinos viaja entero del modelo a la
    respuesta."""

    async def fake(t, *, model="gpt-4o-mini"):  # noqa: ANN001, ARG001
        assert isinstance(t, str) and t.strip()
        return tipo

    monkeypatch.setattr(llm, "clasificar_captura_json", fake)

    r = await client.post(
        "/api/v1/matix/clasificar-captura",
        json={"texto": texto},
    )
    assert r.status_code == 200, r.text
    assert r.json() == {"tipo": tipo}


async def test_texto_vacio_es_400(client: AsyncClient) -> None:
    """Texto en blanco → 400, sin llamar al modelo."""
    r = await client.post(
        "/api/v1/matix/clasificar-captura",
        json={"texto": "   "},
    )
    assert r.status_code == 400, r.text


async def test_requiere_api_key() -> None:
    """Sin la cabecera X-Matix-Key, el router rechaza con 401."""
    from app.main import app

    from httpx import ASGITransport

    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport, base_url="http://test"
    ) as sin_auth:
        r = await sin_auth.post(
            "/api/v1/matix/clasificar-captura",
            json={"texto": "lo que sea"},
        )
    assert r.status_code == 401, r.text
