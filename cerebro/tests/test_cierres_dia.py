"""CRUD de cierres_dia + comportamiento UPSERT."""
from __future__ import annotations

from datetime import date, timedelta

from httpx import AsyncClient


async def test_crud_y_upsert(client: AsyncClient) -> None:
    # Usar una fecha "vieja" que casi seguro no existe para no chocar
    # con datos previos.
    fecha = (date.today() - timedelta(days=365 * 3)).isoformat()

    # Crear
    r = await client.post(
        "/api/v1/cierres_dia",
        json={"fecha": fecha, "items": ["a", "b", "c"]},
    )
    assert r.status_code == 201, r.text
    cid = r.json()["id"]

    try:
        # Listar con filtro
        r = await client.get(f"/api/v1/cierres_dia?fecha={fecha}")
        assert r.status_code == 200
        assert len(r.json()) == 1
        assert r.json()[0]["items"] == ["a", "b", "c"]

        # POST a la misma fecha = UPSERT (mismo id, items distintos)
        r = await client.post(
            "/api/v1/cierres_dia",
            json={"fecha": fecha, "items": ["x", "y"]},
        )
        assert r.status_code == 201, r.text
        assert r.json()["id"] == cid
        assert r.json()["items"] == ["x", "y"]

        # PATCH
        r = await client.patch(
            f"/api/v1/cierres_dia/{cid}",
            json={"nota_extra": "estaba cansado pero hice lo principal"},
        )
        assert r.status_code == 200
        assert r.json()["nota_extra"].startswith("estaba cansado")
    finally:
        await client.delete(f"/api/v1/cierres_dia/{cid}")
