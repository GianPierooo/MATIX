from __future__ import annotations

import uuid

from httpx import AsyncClient


async def test_crud_categoria_ciclo_completo(client: AsyncClient) -> None:
    nombre = f"_test_cat_{uuid.uuid4().hex[:8]}"
    r = await client.post(
        "/api/v1/categorias",
        json={"nombre": nombre, "color": "#FF8800", "icono": "tag"},
    )
    assert r.status_code == 201, r.text
    creada = r.json()
    cid = creada["id"]

    try:
        assert creada["nombre"] == nombre

        r = await client.get(f"/api/v1/categorias/{cid}")
        assert r.status_code == 200

        r = await client.get("/api/v1/categorias")
        assert r.status_code == 200
        assert cid in [c["id"] for c in r.json()]

        r = await client.patch(f"/api/v1/categorias/{cid}", json={"color": "#00CCAA"})
        assert r.status_code == 200
        assert r.json()["color"] == "#00CCAA"
    finally:
        r = await client.delete(f"/api/v1/categorias/{cid}")
        assert r.status_code in (204, 404)


async def test_categoria_nombre_vacio_422(client: AsyncClient) -> None:
    r = await client.post("/api/v1/categorias", json={"nombre": ""})
    assert r.status_code == 422
