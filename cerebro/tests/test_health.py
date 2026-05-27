from __future__ import annotations

from httpx import AsyncClient


async def test_health_ok(client: AsyncClient) -> None:
    r = await client.get("/health")
    assert r.status_code == 200
    data = r.json()
    assert data["status"] == "ok"
    assert "env" in data
