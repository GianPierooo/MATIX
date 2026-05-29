"""Tests del RAG sobre apuntes (Capa 3 Paso 1).

Estos tests SÍ pegan a OpenAI para los embeddings (es la única
forma de validar la búsqueda semántica de punta a punta). Son
lentos comparados con los demás (~3-5 s) y suman ~0.0001 USD al
medidor del medidor global. La firma del test los hace fácilmente
filtrables si en el futuro queremos saltearlos en CI con `-m`.

Validan dos cosas:

1. `indexar_apunte` + `buscar_apuntes` end-to-end: tras crear un
   apunte sobre un tema, búscarlo por una consulta SEMÁNTICAMENTE
   relacionada (no contiene las palabras literales del apunte) lo
   encuentra entre los top-K.

2. El soft-delete del apunte lo saca de la búsqueda (la papelera no
   se ve aunque tenga chunks vivos en `apunte_chunks`).
"""
from __future__ import annotations

import pytest
from httpx import AsyncClient

from app.db import Postgrest
from app.matix.indexador import buscar_apuntes, indexar_apunte
from app.matix.tools import ejecutar_tool


async def test_buscar_apuntes_encuentra_por_significado(
    _fresh_db: Postgrest, client: AsyncClient
):
    """Sembramos un apunte sobre 'cálculo diferencial' y buscamos
    por 'derivadas y razón de cambio' — una consulta que NO contiene
    las palabras literales del apunte pero está semánticamente
    cerca. El apunte sembrado debe aparecer en los resultados."""
    # Apunte con vocabulario distinto a la consulta para forzar
    # match semántico.
    creado = (
        await client.post(
            "/api/v1/apuntes",
            json={
                "titulo": "_test_rag_calculo_intro",
                "contenido": (
                    "Esta materia introduce el concepto de límite y la "
                    "continuidad de funciones reales de una variable. "
                    "Después construye sobre eso para llegar al cálculo "
                    "diferencial: pendientes, tangentes a curvas, "
                    "comportamiento local de una función."
                ),
                "etiquetas": ["test", "cálculo"],
            },
        )
    ).json()
    aid = creado["id"]

    try:
        # Indexamos a mano (BackgroundTask del endpoint no corre con
        # ASGITransport en tests).
        await indexar_apunte(_fresh_db, creado)

        # Búsqueda con vocabulario DISTINTO al del apunte.
        resultados = await buscar_apuntes(
            _fresh_db,
            consulta="derivadas, razón de cambio instantánea, qué es la pendiente",
            top_k=5,
        )

        # Debe haber al menos un resultado.
        assert resultados, "buscar_apuntes no devolvió nada"

        # Nuestro apunte sembrado debe estar entre los resultados.
        ids = [str(r["apunte_id"]) for r in resultados]
        assert aid in ids, (
            f"el apunte sembrado {aid} no apareció en los resultados; "
            f"ids: {ids}"
        )
    finally:
        # Purgar permanente.
        await client.delete(f"/api/v1/apuntes/{aid}/permanente")


async def test_buscar_apuntes_respeta_papelera(
    _fresh_db: Postgrest, client: AsyncClient
):
    """Si el apunte está en la papelera (soft-delete), no debe
    aparecer en los resultados aunque su chunk siga existiendo."""
    creado = (
        await client.post(
            "/api/v1/apuntes",
            json={
                "titulo": "_test_rag_papelera",
                "contenido": (
                    "Notas sobre arquitectura hexagonal y separación "
                    "de capas en aplicaciones backend."
                ),
                "etiquetas": ["test"],
            },
        )
    ).json()
    aid = creado["id"]

    try:
        await indexar_apunte(_fresh_db, creado)

        # Antes de borrar: aparece.
        ids_antes = [
            str(r["apunte_id"])
            for r in await buscar_apuntes(
                _fresh_db,
                consulta="capas en backend, dominio vs infraestructura",
                top_k=5,
            )
        ]
        assert aid in ids_antes

        # Borrado suave.
        r = await client.delete(f"/api/v1/apuntes/{aid}")
        assert r.status_code == 204

        # Después: NO aparece.
        ids_despues = [
            str(r["apunte_id"])
            for r in await buscar_apuntes(
                _fresh_db,
                consulta="capas en backend, dominio vs infraestructura",
                top_k=5,
            )
        ]
        assert aid not in ids_despues, (
            "el apunte en papelera apareció en la búsqueda"
        )

        # Restaurar y verificar que vuelve.
        await client.post(f"/api/v1/apuntes/{aid}/restaurar")
        ids_restaurado = [
            str(r["apunte_id"])
            for r in await buscar_apuntes(
                _fresh_db,
                consulta="capas en backend, dominio vs infraestructura",
                top_k=5,
            )
        ]
        assert aid in ids_restaurado, (
            "el apunte restaurado no volvió a la búsqueda"
        )
    finally:
        await client.delete(f"/api/v1/apuntes/{aid}/permanente")


async def test_tool_buscar_apuntes(_fresh_db: Postgrest, client: AsyncClient):
    """Smoke de la tool dispatcher para `buscar_apuntes`."""
    # Falta consulta → validación
    r = await ejecutar_tool(_fresh_db, "buscar_apuntes", {})
    assert r["ok"] is False
    assert r["tipo"] == "validacion"

    # Consulta vacía → mismo error
    r = await ejecutar_tool(_fresh_db, "buscar_apuntes", {"consulta": "   "})
    assert r["ok"] is False

    # Consulta válida — devuelve resultados (posiblemente vacíos si
    # no hay apuntes), pero `ok=True` y estructura correcta.
    r = await ejecutar_tool(
        _fresh_db,
        "buscar_apuntes",
        {"consulta": "algo improbable_xyz_zzz", "top_k": 3},
    )
    assert r["ok"], r
    assert "resultados" in r["datos"]
    assert isinstance(r["datos"]["resultados"], list)


async def test_crear_apunte_por_tool_queda_buscable(
    _fresh_db: Postgrest, client: AsyncClient
):
    """Un apunte creado por la tool de Matix (la vía de la voz) pasa
    por el pipeline de embeddings igual que uno creado desde la app:
    después se encuentra por significado, no solo por palabras."""
    r = await ejecutar_tool(
        _fresh_db,
        "crear_apunte",
        {
            "titulo": "_test_rag_tool_fotosintesis",
            "contenido": (
                "Las plantas captan luz solar y la usan para convertir "
                "dióxido de carbono y agua en glucosa, liberando oxígeno. "
                "Ocurre en los cloroplastos, sobre todo en las hojas."
            ),
            "etiquetas": ["test"],
        },
    )
    assert r["ok"], r
    aid = r["datos"]["id"]
    try:
        # Consulta con vocabulario DISTINTO al del apunte.
        resultados = await buscar_apuntes(
            _fresh_db,
            consulta="cómo transforman las plantas la energía del sol en alimento",
            top_k=5,
        )
        ids = [str(x["apunte_id"]) for x in resultados]
        assert aid in ids, (
            f"el apunte creado por la tool {aid} no quedó indexado; ids: {ids}"
        )
    finally:
        await client.delete(f"/api/v1/apuntes/{aid}/permanente")


def test_indexador_recorta_apuntes_enormes():
    """El indexador recorta el texto a `_MAX_CHARS_POR_CHUNK` antes
    de embeber, para no mandar cosas absurdas a OpenAI si alguien
    pega un binario o un texto gigante."""
    from app.matix.indexador import _MAX_CHARS_POR_CHUNK, _texto_a_indexar

    apunte = {
        "titulo": "huge",
        "contenido": "x" * (_MAX_CHARS_POR_CHUNK * 2),
        "etiquetas": [],
    }
    texto = _texto_a_indexar(apunte)
    assert len(texto) <= _MAX_CHARS_POR_CHUNK


def test_indexador_apunte_vacio_no_explota():
    """Un apunte sin contenido devuelve string vacío del helper —
    el indexador detecta esto y no llama a OpenAI."""
    from app.matix.indexador import _texto_a_indexar

    assert _texto_a_indexar({"titulo": "", "contenido": "", "etiquetas": []}) == ""
    assert _texto_a_indexar({"titulo": "  ", "contenido": "   "}) == ""
