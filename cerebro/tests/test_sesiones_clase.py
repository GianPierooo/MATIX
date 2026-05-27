from __future__ import annotations

from httpx import AsyncClient


async def test_crud_sesion_ciclo_completo(client: AsyncClient, curso_id: str) -> None:
    r = await client.post(
        "/api/v1/sesiones-clase",
        json={
            "curso_id": curso_id,
            "dia_semana": 1,  # martes
            "hora_inicio": "08:00:00",
            "hora_fin": "10:00:00",
            "ubicacion": "Aula 301",
        },
    )
    assert r.status_code == 201, r.text
    creada = r.json()
    sid = creada["id"]

    try:
        assert creada["dia_semana"] == 1
        assert creada["hora_inicio"] == "08:00:00"

        r = await client.get(f"/api/v1/sesiones-clase/{sid}")
        assert r.status_code == 200

        r = await client.get("/api/v1/sesiones-clase")
        assert r.status_code == 200
        assert sid in [s["id"] for s in r.json()]

        r = await client.patch(
            f"/api/v1/sesiones-clase/{sid}",
            json={"ubicacion": "Aula 302"},
        )
        assert r.status_code == 200
        assert r.json()["ubicacion"] == "Aula 302"
    finally:
        r = await client.delete(f"/api/v1/sesiones-clase/{sid}")
        assert r.status_code in (204, 404)


async def test_sesion_dia_semana_invalido_422(client: AsyncClient, curso_id: str) -> None:
    r = await client.post(
        "/api/v1/sesiones-clase",
        json={
            "curso_id": curso_id,
            "dia_semana": 9,
            "hora_inicio": "08:00:00",
            "hora_fin": "10:00:00",
        },
    )
    assert r.status_code == 422
