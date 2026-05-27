from __future__ import annotations

from httpx import AsyncClient


async def test_crud_curso_ciclo_completo(client: AsyncClient) -> None:
    r = await client.post(
        "/api/v1/cursos",
        json={"nombre": "_test_curso", "profesor": "Prof X", "color": "#2D7FF9"},
    )
    assert r.status_code == 201, r.text
    cid = r.json()["id"]

    try:
        r = await client.get(f"/api/v1/cursos/{cid}")
        assert r.status_code == 200

        r = await client.get("/api/v1/cursos")
        assert r.status_code == 200
        assert cid in [c["id"] for c in r.json()]

        r = await client.patch(f"/api/v1/cursos/{cid}", json={"profesor": "Prof Y"})
        assert r.status_code == 200
        assert r.json()["profesor"] == "Prof Y"
    finally:
        r = await client.delete(f"/api/v1/cursos/{cid}")
        assert r.status_code in (204, 404)
