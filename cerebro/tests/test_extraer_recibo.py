"""Tests del endpoint texto OCR de un recibo → gasto propuesto
(Finanzas-2).

`POST /matix/extraer-recibo` recibe el texto que la app sacó de la foto
de una boleta y devuelve un gasto propuesto (monto, fecha, comercio,
categoría) para que el usuario lo revise y lo guarde. NO persiste nada.

No pegamos al modelo real: monkeypatcheamos `llm.extraer_recibo_json`.
Validamos que el endpoint serializa el monto/fecha, que respeta el monto
null (no inventa cifras) y que rechaza el texto vacío.
"""
from __future__ import annotations

from httpx import AsyncClient

from app.matix import llm


async def test_extrae_monto_fecha_comercio(
    client: AsyncClient, monkeypatch
) -> None:
    async def fake(texto, *, hoy, model="gpt-4o-mini"):  # noqa: ANN001, ARG001
        assert isinstance(hoy, str) and len(hoy) == 10
        return {
            "monto": 45.90,
            "fecha": "2026-05-10",
            "comercio": "Supermercado XYZ",
            "categoria": "Comida",
        }

    monkeypatch.setattr(llm, "extraer_recibo_json", fake)

    r = await client.post(
        "/api/v1/matix/extraer-recibo",
        json={"texto": "SUPERMERCADO XYZ ... TOTAL S/ 45.90 10/05/2026"},
    )
    assert r.status_code == 200, r.text
    recibo = r.json()["recibo"]
    assert recibo["monto"] == 45.90
    assert recibo["fecha"] == "2026-05-10"
    assert recibo["comercio"] == "Supermercado XYZ"
    assert recibo["categoria"] == "Comida"


async def test_monto_null_no_inventa(client: AsyncClient, monkeypatch) -> None:
    """Si el OCR no dio un total claro, monto viene null y la app lo deja
    escribir a mano."""

    async def fake(texto, *, hoy, model="gpt-4o-mini"):  # noqa: ANN001, ARG001
        return {
            "monto": None,
            "fecha": None,
            "comercio": "Tienda borrosa",
            "categoria": None,
        }

    monkeypatch.setattr(llm, "extraer_recibo_json", fake)

    r = await client.post(
        "/api/v1/matix/extraer-recibo",
        json={"texto": "ticket ilegible sin total"},
    )
    assert r.status_code == 200, r.text
    recibo = r.json()["recibo"]
    assert recibo["monto"] is None
    assert recibo["fecha"] is None
    assert recibo["comercio"] == "Tienda borrosa"


async def test_texto_vacio_es_400(client: AsyncClient) -> None:
    r = await client.post("/api/v1/matix/extraer-recibo", json={"texto": "   "})
    assert r.status_code == 400, r.text
