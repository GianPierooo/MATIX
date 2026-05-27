"""Tests de la papelera: DELETE = soft, /restaurar, /permanente.

Tres entidades: tareas, eventos, apuntes. Misma semántica.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from httpx import AsyncClient


async def test_borrar_tarea_es_soft(client: AsyncClient) -> None:
    creada = (
        await client.post(
            "/api/v1/tareas",
            json={"titulo": "_test_papelera_tareas"},
        )
    ).json()
    tid = creada["id"]
    try:
        # DELETE devuelve 204 igual que antes
        r = await client.delete(f"/api/v1/tareas/{tid}")
        assert r.status_code == 204

        # GET por id sigue funcionando (la fila no desapareció)
        r = await client.get(f"/api/v1/tareas/{tid}")
        assert r.status_code == 200
        assert r.json()["eliminado_en"] is not None

        # GET lista normal NO la incluye
        lista = (await client.get("/api/v1/tareas")).json()
        assert all(t["id"] != tid for t in lista)

        # GET ?papelera=true SÍ la incluye
        papelera = (await client.get("/api/v1/tareas?papelera=true")).json()
        assert any(t["id"] == tid for t in papelera)

        # Restaurar: vuelve a la lista normal
        r = await client.post(f"/api/v1/tareas/{tid}/restaurar")
        assert r.status_code == 200
        assert r.json()["eliminado_en"] is None
        lista = (await client.get("/api/v1/tareas")).json()
        assert any(t["id"] == tid for t in lista)
    finally:
        # Limpieza dura
        await client.delete(f"/api/v1/tareas/{tid}/permanente")


async def test_permanente_destruye_de_verdad(client: AsyncClient) -> None:
    creada = (
        await client.post(
            "/api/v1/tareas",
            json={"titulo": "_test_papelera_permanente"},
        )
    ).json()
    tid = creada["id"]
    # Soft delete, luego permanente
    await client.delete(f"/api/v1/tareas/{tid}")
    r = await client.delete(f"/api/v1/tareas/{tid}/permanente")
    assert r.status_code == 204
    # Ya no está ni en la papelera
    r = await client.get(f"/api/v1/tareas/{tid}")
    assert r.status_code == 404


async def test_borrar_evento_es_soft(client: AsyncClient) -> None:
    inicia = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()
    creada = (
        await client.post(
            "/api/v1/eventos",
            json={"titulo": "_test_papelera_eventos", "inicia_en": inicia},
        )
    ).json()
    eid = creada["id"]
    try:
        await client.delete(f"/api/v1/eventos/{eid}")
        # No aparece en la lista normal
        lista = (await client.get("/api/v1/eventos")).json()
        assert all(e["id"] != eid for e in lista)
        # Aparece en la papelera
        pap = (await client.get("/api/v1/eventos?papelera=true")).json()
        assert any(e["id"] == eid for e in pap)
        # Restaurar
        await client.post(f"/api/v1/eventos/{eid}/restaurar")
        lista = (await client.get("/api/v1/eventos")).json()
        assert any(e["id"] == eid for e in lista)
    finally:
        await client.delete(f"/api/v1/eventos/{eid}/permanente")


async def test_borrar_apunte_es_soft(client: AsyncClient) -> None:
    creada = (
        await client.post(
            "/api/v1/apuntes",
            json={"titulo": "_test_papelera_apuntes", "contenido": "x"},
        )
    ).json()
    aid = creada["id"]
    try:
        await client.delete(f"/api/v1/apuntes/{aid}")
        lista = (await client.get("/api/v1/apuntes")).json()
        assert all(a["id"] != aid for a in lista)
        pap = (await client.get("/api/v1/apuntes?papelera=true")).json()
        assert any(a["id"] == aid for a in pap)
    finally:
        await client.delete(f"/api/v1/apuntes/{aid}/permanente")
