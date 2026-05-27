"""Cobertura adicional de tools (Capa 2 Paso 5.1 — refuerzos).

Complementa `test_matix_tools_capacidad.py` con los caminos
felices y los edge cases que quedaron sin probar:

- `consultar_uso` — lectura del medidor.
- `editar_proyecto` (happy path) — cambia nombre/línea de meta.
- `aparcar_proyecto` (camino feliz partiendo de activo).
- `editar_tarea` que mueve la tarea de proyecto.
- `editar_apunte` con partial update — cambiar solo `etiquetas`.
- `marcar_accion_siguiente_hecha` happy path completo.
"""
from __future__ import annotations

from httpx import AsyncClient

from app.db import Postgrest
from app.matix.tools import ejecutar_tool
from app.matix.uso import medidor


# ── consultar_uso ────────────────────────────────────────────────────


async def test_consultar_uso_devuelve_estructura_esperada(
    _fresh_db: Postgrest,
) -> None:
    medidor.reiniciar()
    r = await ejecutar_tool(_fresh_db, "consultar_uso", {})
    assert r["ok"], r
    datos = r["datos"]
    # Todos los campos clave presentes y con tipos correctos
    assert datos["total_tokens"] == 0
    assert datos["prompt_tokens"] == 0
    assert datos["completion_tokens"] == 0
    assert datos["cached_prompt_tokens"] == 0
    assert datos["llamadas_chat"] == 0
    assert datos["segundos_whisper"] == 0
    assert datos["llamadas_whisper"] == 0
    assert datos["costo_usd"] == 0


async def test_consultar_uso_refleja_actividad_registrada(
    _fresh_db: Postgrest,
) -> None:
    medidor.reiniciar()
    medidor.registrar_chat(
        {"prompt_tokens": 1234, "completion_tokens": 567}
    )
    r = await ejecutar_tool(_fresh_db, "consultar_uso", {})
    assert r["ok"]
    assert r["datos"]["prompt_tokens"] == 1234
    assert r["datos"]["completion_tokens"] == 567
    assert r["datos"]["llamadas_chat"] == 1
    assert r["datos"]["costo_usd"] > 0


# ── editar_proyecto happy path ──────────────────────────────────────


async def test_editar_proyecto_cambia_campos_libres(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    r = await ejecutar_tool(
        _fresh_db,
        "crear_proyecto",
        {"nombre": "_test_editar_happy", "estado": "aparcado"},
    )
    pid = r["datos"]["id"]
    try:
        r = await ejecutar_tool(
            _fresh_db,
            "editar_proyecto",
            {
                "proyecto_id": pid,
                "nombre": "_test_editar_renombrado",
                "linea_meta": "v1 publicada",
                "color": "#FF8800",
            },
        )
        assert r["ok"], r
        actual = (await client.get(f"/api/v1/proyectos/{pid}")).json()
        assert actual["nombre"] == "_test_editar_renombrado"
        assert actual["linea_meta"] == "v1 publicada"
        assert actual["color"] == "#FF8800"
        # estado no cambió
        assert actual["estado"] == "aparcado"
    finally:
        await client.delete(f"/api/v1/proyectos/{pid}")


# ── aparcar_proyecto desde activo ───────────────────────────────────


async def test_aparcar_proyecto_desde_activo(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    """Cubre la transición activo → aparcado (la inversa de la del
    test de reactivar)."""
    # Buscamos un proyecto activo en la BD seed o creamos uno
    # respetando el tope.
    activos = [
        p
        for p in (await client.get("/api/v1/proyectos")).json()
        if p["estado"] == "activo"
    ]
    creado_para_test = False
    if len(activos) >= 3:
        # Saltamos: no podemos crear un cuarto activo, y aparcar uno
        # real del usuario sería invasivo.
        import pytest

        pytest.skip("3 activos en uso; no aparcamos uno real")
    else:
        r = await ejecutar_tool(
            _fresh_db,
            "crear_proyecto",
            {"nombre": "_test_aparcar_desde_activo", "estado": "activo"},
        )
        assert r["ok"]
        pid = r["datos"]["id"]
        creado_para_test = True

    try:
        r = await ejecutar_tool(
            _fresh_db, "aparcar_proyecto", {"proyecto_id": pid}
        )
        assert r["ok"], r
        assert r["datos"]["estado"] == "aparcado"
        assert r["datos"]["estado_anterior"] == "activo"
        actual = (await client.get(f"/api/v1/proyectos/{pid}")).json()
        assert actual["estado"] == "aparcado"
        assert actual["inactivo_desde"] is not None
    finally:
        if creado_para_test:
            await client.delete(f"/api/v1/proyectos/{pid}")


# ── editar_tarea: mover de proyecto ─────────────────────────────────


async def test_editar_tarea_mueve_de_proyecto(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    """Editar `proyecto_id` mueve la tarea entre proyectos. El cerebro
    deja `proyecto_id=null` si se pasa explícitamente null vía el
    Update schema."""
    # Crear proyecto destino aparcado para no tocar tope
    p = await ejecutar_tool(
        _fresh_db,
        "crear_proyecto",
        {"nombre": "_test_mover_destino", "estado": "aparcado"},
    )
    pid = p["datos"]["id"]
    t = (
        await client.post(
            "/api/v1/tareas", json={"titulo": "_test_mover_tarea"}
        )
    ).json()
    tid = t["id"]
    try:
        r = await ejecutar_tool(
            _fresh_db,
            "editar_tarea",
            {"tarea_id": tid, "proyecto_id": pid},
        )
        assert r["ok"], r
        actual = (await client.get(f"/api/v1/tareas/{tid}")).json()
        assert actual["proyecto_id"] == pid
    finally:
        await client.delete(f"/api/v1/tareas/{tid}/permanente")
        await client.delete(f"/api/v1/proyectos/{pid}")


# ── editar_apunte: partial update (solo etiquetas) ──────────────────


async def test_editar_apunte_solo_etiquetas(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    creada = (
        await client.post(
            "/api/v1/apuntes",
            json={
                "titulo": "_test_ap_solo_tags",
                "contenido": "contenido original sin tocar",
                "etiquetas": ["uno"],
            },
        )
    ).json()
    aid = creada["id"]
    try:
        r = await ejecutar_tool(
            _fresh_db,
            "editar_apunte",
            {"apunte_id": aid, "etiquetas": ["dos", "tres"]},
        )
        assert r["ok"], r
        actual = (await client.get(f"/api/v1/apuntes/{aid}")).json()
        assert "dos" in actual["etiquetas"]
        assert "tres" in actual["etiquetas"]
        # El contenido NO se tocó
        assert actual["contenido"] == "contenido original sin tocar"
        assert actual["titulo"] == "_test_ap_solo_tags"
    finally:
        await client.delete(f"/api/v1/apuntes/{aid}/permanente")


# ── marcar_accion_siguiente_hecha — happy path ──────────────────────


async def test_accion_siguiente_happy_path_completo(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    """Crea proyecto aparcado con tarea_siguiente, llama la tool,
    verifica que la tarea quedó completada y el proyecto sin acción
    siguiente."""
    # Tarea libre primero
    t = (
        await client.post(
            "/api/v1/tareas",
            json={"titulo": "_test_acc_sig_happy_tarea"},
        )
    ).json()
    tid = t["id"]
    p = (
        await client.post(
            "/api/v1/proyectos",
            json={
                "nombre": "_test_acc_sig_happy_proy",
                "estado": "aparcado",
                "tarea_siguiente_id": tid,
            },
        )
    ).json()
    pid = p["id"]
    try:
        r = await ejecutar_tool(
            _fresh_db,
            "marcar_accion_siguiente_hecha",
            {"proyecto_id": pid},
        )
        assert r["ok"], r
        assert r["datos"]["proyecto_nombre"] == "_test_acc_sig_happy_proy"
        assert r["datos"]["tarea_completada"] == "_test_acc_sig_happy_tarea"
        tarea_actual = (await client.get(f"/api/v1/tareas/{tid}")).json()
        assert tarea_actual["completada"] is True
        proyecto_actual = (
            await client.get(f"/api/v1/proyectos/{pid}")
        ).json()
        assert proyecto_actual["tarea_siguiente_id"] is None
    finally:
        await client.delete(f"/api/v1/proyectos/{pid}")
        await client.delete(f"/api/v1/tareas/{tid}/permanente")
