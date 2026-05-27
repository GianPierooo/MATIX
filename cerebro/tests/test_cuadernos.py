from __future__ import annotations

from httpx import AsyncClient


async def test_crud_cuaderno_ciclo_completo(client: AsyncClient, curso_id: str) -> None:
    r = await client.post(
        "/api/v1/cuadernos",
        json={"nombre": "_test_cuaderno", "color": "#21D07A", "curso_id": curso_id},
    )
    assert r.status_code == 201, r.text
    creada = r.json()
    cid = creada["id"]

    try:
        assert creada["nombre"] == "_test_cuaderno"
        assert creada["curso_id"] == curso_id

        r = await client.get(f"/api/v1/cuadernos/{cid}")
        assert r.status_code == 200

        r = await client.get("/api/v1/cuadernos")
        assert r.status_code == 200
        assert cid in [c["id"] for c in r.json()]

        r = await client.patch(f"/api/v1/cuadernos/{cid}", json={"color": "#FF4D5E"})
        assert r.status_code == 200
        assert r.json()["color"] == "#FF4D5E"
    finally:
        r = await client.delete(f"/api/v1/cuadernos/{cid}")
        assert r.status_code in (204, 404)
