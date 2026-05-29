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


async def test_recurrencia_round_trip(client: AsyncClient) -> None:
    """La regla de recurrencia (Cal-3) viaja ida y vuelta y se puede limpiar.

    El cerebro solo guarda/lee la regla; la expansión de ocurrencias vive
    en la app. Verificamos que las 5 columnas se persisten, que el array de
    días de semana sobrevive, y que un PATCH con null las limpia (volver a
    evento único).
    """
    r = await client.post(
        "/api/v1/eventos",
        json={
            "titulo": "_test_recurrencia",
            "inicia_en": "2026-06-15T10:00:00Z",
            # Clases lunes y miércoles hasta fin de ciclo.
            "recurrencia_freq": "semanal",
            "recurrencia_dias_semana": [1, 3],
            "recurrencia_fin_tipo": "hasta",
            "recurrencia_hasta": "2026-07-15",
        },
    )
    assert r.status_code == 201, r.text
    creada = r.json()
    eid = creada["id"]

    try:
        assert creada["recurrencia_freq"] == "semanal"
        assert creada["recurrencia_dias_semana"] == [1, 3]
        assert creada["recurrencia_fin_tipo"] == "hasta"
        assert creada["recurrencia_hasta"] == "2026-07-15"

        # Cambiar la regla de toda la serie: diaria, 5 repeticiones.
        r = await client.patch(
            f"/api/v1/eventos/{eid}",
            json={
                "recurrencia_freq": "diaria",
                "recurrencia_dias_semana": None,
                "recurrencia_fin_tipo": "conteo",
                "recurrencia_hasta": None,
                "recurrencia_conteo": 5,
            },
        )
        assert r.status_code == 200
        actualizada = r.json()
        assert actualizada["recurrencia_freq"] == "diaria"
        assert actualizada["recurrencia_conteo"] == 5
        assert actualizada["recurrencia_hasta"] is None

        # Volver a evento único: toda la recurrencia a null.
        r = await client.patch(
            f"/api/v1/eventos/{eid}",
            json={
                "recurrencia_freq": None,
                "recurrencia_dias_semana": None,
                "recurrencia_fin_tipo": None,
                "recurrencia_hasta": None,
                "recurrencia_conteo": None,
            },
        )
        assert r.status_code == 200
        limpia = r.json()
        assert limpia["recurrencia_freq"] is None
        assert limpia["recurrencia_dias_semana"] is None
        assert limpia["recurrencia_fin_tipo"] is None
        assert limpia["recurrencia_conteo"] is None
    finally:
        r = await client.delete(f"/api/v1/eventos/{eid}/permanente")
        assert r.status_code in (204, 404)
