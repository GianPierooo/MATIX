from __future__ import annotations

from httpx import AsyncClient


async def test_crud_evento_ciclo_completo(client: AsyncClient) -> None:
    r = await client.post(
        "/api/v1/eventos",
        json={
            "titulo": "_test_evento",
            "descripcion": "reunión de prueba",
            "inicia_en": "2026-06-15T10:00:00Z",
            "termina_en": "2026-06-15T11:00:00Z",
            "ubicacion": "Sala 1",
        },
    )
    assert r.status_code == 201, r.text
    creada = r.json()
    eid = creada["id"]

    try:
        assert creada["titulo"] == "_test_evento"
        assert creada["todo_el_dia"] is False

        r = await client.get(f"/api/v1/eventos/{eid}")
        assert r.status_code == 200

        r = await client.get("/api/v1/eventos")
        assert r.status_code == 200
        assert eid in [e["id"] for e in r.json()]

        r = await client.patch(f"/api/v1/eventos/{eid}", json={"todo_el_dia": True})
        assert r.status_code == 200
        assert r.json()["todo_el_dia"] is True
    finally:
        r = await client.delete(f"/api/v1/eventos/{eid}/permanente")
        assert r.status_code in (204, 404)
