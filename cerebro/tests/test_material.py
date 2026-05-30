"""Tests de la biblioteca de material de aprendizaje (Fase 1).

Como los del RAG de apuntes, SÍ pegan a OpenAI para los embeddings (es
la única forma de validar la búsqueda semántica de punta a punta) y
requieren el Supabase de test con la migración 0015 aplicada.

Validan:
1. Ingestar es idempotente por skill+bloque: re-ingestar el mismo par
   reemplaza (no duplica).
2. La búsqueda filtra por skill y por bloque, y NO se mezcla con apuntes.
"""
from __future__ import annotations

from httpx import AsyncClient

from app.db import Postgrest
from app.matix.biblioteca import buscar_material


async def _contar(db: Postgrest, skill: str, bloque: str) -> int:
    filas = await db.list(
        "material_chunks",
        filters={"skill": skill, "bloque": bloque},
        limit=1000,
    )
    return len(filas)


async def _purgar(db: Postgrest, skill: str) -> None:
    await db.delete_where("material_chunks", filters={"skill": skill})


async def test_ingestar_es_idempotente_por_skill_bloque(
    _fresh_db: Postgrest, client: AsyncClient
):
    """Ingestar dos veces el mismo skill+bloque reemplaza, no acumula."""
    skill = "_test_calistenia"
    try:
        r1 = await client.post(
            "/api/v1/material/ingestar",
            json={
                "skill": skill,
                "bloque": "bloque_3",
                "fuente": "bloque_3.md",
                "piezas": ["Dominadas y fondos.", "Progresión a la front lever."],
            },
        )
        assert r1.status_code == 200, r1.text
        body1 = r1.json()
        assert body1["creados"] == 2
        assert body1["reemplazados"] == 0
        assert await _contar(_fresh_db, skill, "bloque_3") == 2

        # Re-ingesta del MISMO skill+bloque con contenido distinto.
        r2 = await client.post(
            "/api/v1/material/ingestar",
            json={
                "skill": skill,
                "bloque": "bloque_3",
                "fuente": "bloque_3.md",
                "piezas": ["Solo una pieza nueva."],
            },
        )
        assert r2.status_code == 200, r2.text
        body2 = r2.json()
        assert body2["creados"] == 1
        assert body2["reemplazados"] == 2  # borró las 2 viejas
        # No se acumuló: queda 1, no 3.
        assert await _contar(_fresh_db, skill, "bloque_3") == 1
    finally:
        await _purgar(_fresh_db, skill)


async def test_buscar_filtra_por_skill_y_bloque(
    _fresh_db: Postgrest, client: AsyncClient
):
    """El material de un bloque no contamina la búsqueda de otro, y el
    filtro por skill aísla cada track."""
    skill = "_test_ingles"
    try:
        await client.post(
            "/api/v1/material/ingestar",
            json={
                "skill": skill,
                "bloque": "bloque_1",
                "fuente": "b1",
                "piezas": ["Present simple: rutinas y hechos generales."],
            },
        )
        await client.post(
            "/api/v1/material/ingestar",
            json={
                "skill": skill,
                "bloque": "bloque_2",
                "fuente": "b2",
                "piezas": ["Past perfect: acciones antes de otra pasada."],
            },
        )

        # Filtrando por bloque_2 solo debe traer material de ese bloque.
        filas = await buscar_material(
            _fresh_db,
            consulta="tiempos verbales del pasado",
            skill=skill,
            bloque="bloque_2",
            top_k=5,
        )
        assert filas, "no devolvió material"
        assert all(f["bloque"] == "bloque_2" for f in filas)
        assert all(f["skill"] == skill for f in filas)
    finally:
        await _purgar(_fresh_db, skill)


async def test_skill_bloque_obligatorios_400(client: AsyncClient):
    r = await client.post(
        "/api/v1/material/ingestar",
        json={"skill": "", "bloque": "x", "piezas": ["algo"]},
    )
    assert r.status_code == 422  # Pydantic: min_length=1
