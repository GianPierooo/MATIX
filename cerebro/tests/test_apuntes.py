from __future__ import annotations

from httpx import AsyncClient


async def test_crud_apunte_ciclo_completo(client: AsyncClient, cuaderno_id: str) -> None:
    r = await client.post(
        "/api/v1/apuntes",
        json={
            "titulo": "_test_apunte",
            "contenido": "contenido inicial",
            "cuaderno_id": cuaderno_id,
            "etiquetas": ["prueba", "ejemplo"],
            "adjuntos": [{"url": "https://x.invalid/a.png", "tipo": "image", "nombre": "a.png"}],
        },
    )
    assert r.status_code == 201, r.text
    creada = r.json()
    aid = creada["id"]

    try:
        assert creada["titulo"] == "_test_apunte"
        assert creada["etiquetas"] == ["prueba", "ejemplo"]
        assert len(creada["adjuntos"]) == 1

        r = await client.get(f"/api/v1/apuntes/{aid}")
        assert r.status_code == 200

        r = await client.get("/api/v1/apuntes")
        assert r.status_code == 200
        assert aid in [a["id"] for a in r.json()]

        r = await client.patch(
            f"/api/v1/apuntes/{aid}",
            json={"contenido": "contenido editado", "etiquetas": ["solo-una"]},
        )
        assert r.status_code == 200
        actualizado = r.json()
        assert actualizado["contenido"] == "contenido editado"
        assert actualizado["etiquetas"] == ["solo-una"]
    finally:
        r = await client.delete(f"/api/v1/apuntes/{aid}/permanente")
        assert r.status_code in (204, 404)


async def test_apunte_titulo_vacio_422(client: AsyncClient) -> None:
    r = await client.post("/api/v1/apuntes", json={"titulo": ""})
    assert r.status_code == 422
