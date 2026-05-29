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


async def test_recordatorio_offset_round_trip(client: AsyncClient) -> None:
    """El offset (Cal-2) y su espejo `recordar_en` viajan ida y vuelta.

    El cerebro no calcula el espejo: lo manda la app. Aquí solo
    verificamos que ambos campos se persisten y que un PATCH del offset
    los actualiza (incluido limpiarlos con null).
    """
    r = await client.post(
        "/api/v1/eventos",
        json={
            "titulo": "_test_recordatorio",
            "inicia_en": "2026-06-15T10:00:00Z",
            # 10 min antes → espejo que la app derivó.
            "recordatorio_offset_min": 10,
            "recordar_en": "2026-06-15T09:50:00Z",
        },
    )
    assert r.status_code == 201, r.text
    creada = r.json()
    eid = creada["id"]

    try:
        assert creada["recordatorio_offset_min"] == 10
        assert creada["recordar_en"] is not None

        # Cambiar a "1 día antes": la app manda offset + nuevo espejo.
        r = await client.patch(
            f"/api/v1/eventos/{eid}",
            json={
                "recordatorio_offset_min": 1440,
                "recordar_en": "2026-06-14T10:00:00Z",
            },
        )
        assert r.status_code == 200
        assert r.json()["recordatorio_offset_min"] == 1440

        # Quitar el recordatorio: ambos a null.
        r = await client.patch(
            f"/api/v1/eventos/{eid}",
            json={"recordatorio_offset_min": None, "recordar_en": None},
        )
        assert r.status_code == 200
        assert r.json()["recordatorio_offset_min"] is None
        assert r.json()["recordar_en"] is None
    finally:
        r = await client.delete(f"/api/v1/eventos/{eid}/permanente")
        assert r.status_code in (204, 404)
