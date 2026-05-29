"""Tests del CRUD de tracks de aprendizaje (Fase 2).

Integración contra la Supabase de test. Crean tracks `_test_…` y limpian.
Cubre: tope de 3 activos, fijar posición, activar/pausar, 404.
"""
from __future__ import annotations

from httpx import AsyncClient


async def _crear(client: AsyncClient, nombre: str, estado: str = "activo") -> dict:
    r = await client.post(
        "/api/v1/tracks", json={"nombre": nombre, "estado": estado}
    )
    assert r.status_code == 201, r.text
    return r.json()


async def test_crud_y_posicion(client: AsyncClient) -> None:
    t = await _crear(client, "_test_calistenia")
    tid = t["id"]
    try:
        assert t["estado"] == "activo"
        # Fijar posición.
        r = await client.patch(
            f"/api/v1/tracks/{tid}",
            json={"bloque_actual": "Bloque 3", "semana": 2, "dia": 4},
        )
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["bloque_actual"] == "Bloque 3"
        assert body["semana"] == 2
        assert body["dia"] == 4
        # Pausar y reactivar.
        r = await client.patch(f"/api/v1/tracks/{tid}", json={"estado": "pausado"})
        assert r.json()["estado"] == "pausado"
        r = await client.patch(f"/api/v1/tracks/{tid}", json={"estado": "activo"})
        assert r.json()["estado"] == "activo"
    finally:
        await client.delete(f"/api/v1/tracks/{tid}")


async def test_tope_3_activos(client: AsyncClient) -> None:
    ids: list[str] = []
    try:
        for i in range(3):
            ids.append((await _crear(client, f"_test_track_{i}"))["id"])
        # El 4.º activo debe rebotar con 409.
        r = await client.post(
            "/api/v1/tracks", json={"nombre": "_test_track_4"}
        )
        assert r.status_code == 409, r.text
        # Crear uno pausado SÍ se permite (no cuenta para el tope).
        pausado = await _crear(client, "_test_track_pausado", estado="pausado")
        ids.append(pausado["id"])
        # Reactivarlo estando en el tope rebota.
        r = await client.patch(
            f"/api/v1/tracks/{pausado['id']}", json={"estado": "activo"}
        )
        assert r.status_code == 409
        # Pausar uno de los activos libera el cupo.
        r = await client.patch(
            f"/api/v1/tracks/{ids[0]}", json={"estado": "pausado"}
        )
        assert r.status_code == 200
        r = await client.patch(
            f"/api/v1/tracks/{pausado['id']}", json={"estado": "activo"}
        )
        assert r.status_code == 200
    finally:
        for tid in ids:
            await client.delete(f"/api/v1/tracks/{tid}")


async def test_obtener_inexistente_404(client: AsyncClient) -> None:
    falso = "00000000-0000-0000-0000-000000000000"
    r = await client.get(f"/api/v1/tracks/{falso}")
    assert r.status_code == 404


async def test_requiere_api_key(client_anon: AsyncClient) -> None:
    r = await client_anon.get("/api/v1/tracks")
    assert r.status_code == 401
