"""Tests del reflote de ideas (Capa 7): archivar y retomar.

Integración contra la Supabase de test (ver conftest). Crean un apunte
`_test_…`, ejercitan los endpoints y limpian con `/permanente`.

- archivar → setea `archivado_en` (sale del reflote para siempre).
- retomar → toca el apunte (`actualizado_en` avanza), sin tocar
  `archivado_en`.
- 404 cuando el apunte no existe.
"""
from __future__ import annotations

from httpx import AsyncClient


async def test_archivar_setea_archivado_en(client: AsyncClient) -> None:
    r = await client.post("/api/v1/apuntes", json={"titulo": "_test_reflote_arch"})
    assert r.status_code == 201, r.text
    aid = r.json()["id"]
    try:
        assert r.json()["archivado_en"] is None

        r = await client.post(f"/api/v1/apuntes/{aid}/archivar", json={})
        assert r.status_code == 200, r.text
        assert r.json()["archivado_en"] is not None

        # Sigue en la lista de Apuntes (archivar NO es borrar).
        r = await client.get("/api/v1/apuntes")
        assert aid in [a["id"] for a in r.json()]
    finally:
        await client.delete(f"/api/v1/apuntes/{aid}/permanente")


async def test_retomar_toca_sin_archivar(client: AsyncClient) -> None:
    r = await client.post("/api/v1/apuntes", json={"titulo": "_test_reflote_ret"})
    assert r.status_code == 201, r.text
    creado = r.json()
    aid = creado["id"]
    try:
        r = await client.post(f"/api/v1/apuntes/{aid}/retomar", json={})
        assert r.status_code == 200, r.text
        tocado = r.json()
        # Sigue sin archivar y `actualizado_en` no retrocede.
        assert tocado["archivado_en"] is None
        assert tocado["actualizado_en"] >= creado["actualizado_en"]
    finally:
        await client.delete(f"/api/v1/apuntes/{aid}/permanente")


async def test_archivar_inexistente_404(client: AsyncClient) -> None:
    falso = "00000000-0000-0000-0000-000000000000"
    r = await client.post(f"/api/v1/apuntes/{falso}/archivar", json={})
    assert r.status_code == 404


async def test_retomar_inexistente_404(client: AsyncClient) -> None:
    falso = "00000000-0000-0000-0000-000000000000"
    r = await client.post(f"/api/v1/apuntes/{falso}/retomar", json={})
    assert r.status_code == 404
