"""Tests del CRUD de `movimientos` (Finanzas-1).

Ciclo completo crear → leer → listar → editar → borrar, más validación
(monto > 0, tipo válido). Pegan al Supabase de TEST vía el `client`
fixture; limpian en `finally`. El balance/resumen por mes es lógica de
la app (ver el test de dominio en la app), no del cerebro.
"""
from __future__ import annotations

from httpx import AsyncClient


async def test_crud_movimiento_ciclo_completo(client: AsyncClient) -> None:
    r = await client.post(
        "/api/v1/movimientos",
        json={
            "tipo": "gasto",
            "monto": 42.50,
            "categoria": "_test_comida",
            "fecha": "2026-05-10",
            "nota": "almuerzo",
        },
    )
    assert r.status_code == 201, r.text
    creado = r.json()
    mid = creado["id"]

    try:
        assert creado["tipo"] == "gasto"
        assert creado["monto"] == 42.5
        assert creado["categoria"] == "_test_comida"
        assert creado["fecha"] == "2026-05-10"
        assert creado["nota"] == "almuerzo"

        # Obtener por id.
        r = await client.get(f"/api/v1/movimientos/{mid}")
        assert r.status_code == 200

        # Aparece en la lista.
        r = await client.get("/api/v1/movimientos")
        assert r.status_code == 200
        assert mid in [m["id"] for m in r.json()]

        # Editar: cambia a ingreso y otro monto.
        r = await client.patch(
            f"/api/v1/movimientos/{mid}",
            json={"tipo": "ingreso", "monto": 1500, "nota": "sueldo"},
        )
        assert r.status_code == 200, r.text
        editado = r.json()
        assert editado["tipo"] == "ingreso"
        assert editado["monto"] == 1500
        assert editado["nota"] == "sueldo"
        # Lo no enviado se mantiene.
        assert editado["categoria"] == "_test_comida"
    finally:
        r = await client.delete(f"/api/v1/movimientos/{mid}")
        assert r.status_code in (204, 404)

    # Tras borrar, 404.
    r = await client.get(f"/api/v1/movimientos/{mid}")
    assert r.status_code == 404


async def test_crear_sin_fecha_usa_hoy(client: AsyncClient) -> None:
    """Sin `fecha`, la BD pone current_date (no revienta)."""
    r = await client.post(
        "/api/v1/movimientos",
        json={"tipo": "ingreso", "monto": 10, "categoria": "_test_sin_fecha"},
    )
    assert r.status_code == 201, r.text
    mid = r.json()["id"]
    try:
        assert r.json()["fecha"] is not None
    finally:
        await client.delete(f"/api/v1/movimientos/{mid}")


async def test_monto_no_positivo_es_422(client: AsyncClient) -> None:
    r = await client.post(
        "/api/v1/movimientos",
        json={"tipo": "gasto", "monto": 0, "categoria": "_test_x"},
    )
    assert r.status_code == 422


async def test_tipo_invalido_es_422(client: AsyncClient) -> None:
    r = await client.post(
        "/api/v1/movimientos",
        json={"tipo": "regalo", "monto": 5, "categoria": "_test_x"},
    )
    assert r.status_code == 422


async def test_obtener_inexistente_es_404(client: AsyncClient) -> None:
    r = await client.get(
        "/api/v1/movimientos/00000000-0000-0000-0000-000000000000"
    )
    assert r.status_code == 404
