from __future__ import annotations

from httpx import AsyncClient


async def test_crud_evaluacion_ciclo_completo(client: AsyncClient, curso_id: str) -> None:
    r = await client.post(
        "/api/v1/evaluaciones",
        json={
            "curso_id": curso_id,
            "titulo": "_test_eval",
            "tipo": "examen",
            "fecha": "2026-06-10T09:00:00Z",
            "descripcion": "parcial 1",
            "peso": 30,
            "nota_maxima": 20,
        },
    )
    assert r.status_code == 201, r.text
    creada = r.json()
    eid = creada["id"]

    try:
        assert creada["tipo"] == "examen"
        assert creada["descripcion"] == "parcial 1"

        r = await client.get(f"/api/v1/evaluaciones/{eid}")
        assert r.status_code == 200

        r = await client.get("/api/v1/evaluaciones")
        assert r.status_code == 200
        assert eid in [e["id"] for e in r.json()]

        r = await client.patch(
            f"/api/v1/evaluaciones/{eid}",
            json={"nota_obtenida": 17.5},
        )
        assert r.status_code == 200
        assert r.json()["nota_obtenida"] == 17.5
    finally:
        r = await client.delete(f"/api/v1/evaluaciones/{eid}")
        assert r.status_code in (204, 404)


async def test_evaluacion_tipo_invalido_422(client: AsyncClient, curso_id: str) -> None:
    r = await client.post(
        "/api/v1/evaluaciones",
        json={
            "curso_id": curso_id,
            "titulo": "_test_tipo",
            "tipo": "tarea",  # no está en el enum
            "fecha": "2026-06-10T09:00:00Z",
        },
    )
    assert r.status_code == 422
