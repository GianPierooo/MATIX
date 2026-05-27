from __future__ import annotations

from httpx import AsyncClient


async def test_crud_profile_ciclo_completo(client: AsyncClient) -> None:
    # Crear
    r = await client.post(
        "/api/v1/profile",
        json={"nombre": "_test_profile", "zona_horaria": "America/Lima", "tema": "dark"},
    )
    assert r.status_code == 201, r.text
    creada = r.json()
    pid = creada["id"]

    try:
        assert creada["nombre"] == "_test_profile"
        assert creada["tema"] == "dark"

        # Leer
        r = await client.get(f"/api/v1/profile/{pid}")
        assert r.status_code == 200
        assert r.json()["id"] == pid

        # Listar
        r = await client.get("/api/v1/profile")
        assert r.status_code == 200
        assert pid in [p["id"] for p in r.json()]

        # Actualizar
        r = await client.patch(f"/api/v1/profile/{pid}", json={"tema": "light"})
        assert r.status_code == 200
        assert r.json()["tema"] == "light"
    finally:
        r = await client.delete(f"/api/v1/profile/{pid}")
        assert r.status_code in (204, 404)


async def test_profile_tema_invalido_422(client: AsyncClient) -> None:
    r = await client.post("/api/v1/profile", json={"tema": "purpura"})
    assert r.status_code == 422
