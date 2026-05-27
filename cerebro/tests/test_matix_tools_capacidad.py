"""Tests de la tanda de tools de Capa 2 Paso 5 — capacidad total
de Matix sobre el hub.

Verifica:
- editar / eliminar para tareas, eventos, apuntes
- crear / editar / aparcar / terminar / reactivar para proyectos
- tope de 3 proyectos activos: crear y reactivar lo respetan
- eliminar es reversible (sigue en BD con `eliminado_en`)
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from httpx import AsyncClient

from app.db import Postgrest
from app.matix.tools import ejecutar_tool


# ── tareas: editar + eliminar ───────────────────────────────────────


async def test_editar_tarea(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    creada = (
        await client.post(
            "/api/v1/tareas",
            json={"titulo": "_test_tool_editar", "prioridad": "media"},
        )
    ).json()
    tid = creada["id"]
    try:
        r = await ejecutar_tool(
            _fresh_db,
            "editar_tarea",
            {"tarea_id": tid, "titulo": "Renombrada", "prioridad": "alta"},
        )
        assert r["ok"], r
        actual = (await client.get(f"/api/v1/tareas/{tid}")).json()
        assert actual["titulo"] == "Renombrada"
        assert actual["prioridad"] == "alta"
    finally:
        await client.delete(f"/api/v1/tareas/{tid}/permanente")


async def test_editar_tarea_sin_campos(_fresh_db: Postgrest) -> None:
    # Pasar solo el id sin campos → validación
    from uuid import uuid4

    r = await ejecutar_tool(
        _fresh_db, "editar_tarea", {"tarea_id": str(uuid4())}
    )
    assert r["ok"] is False
    assert r["tipo"] == "validacion"


async def test_eliminar_tarea_es_reversible(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    creada = (
        await client.post(
            "/api/v1/tareas", json={"titulo": "_test_tool_eliminar"}
        )
    ).json()
    tid = creada["id"]
    try:
        r = await ejecutar_tool(_fresh_db, "eliminar_tarea", {"tarea_id": tid})
        assert r["ok"], r
        assert r["datos"]["reversible"] is True
        # La fila sigue existiendo
        actual = (await client.get(f"/api/v1/tareas/{tid}")).json()
        assert actual["eliminado_en"] is not None
    finally:
        await client.delete(f"/api/v1/tareas/{tid}/permanente")


# ── eventos: editar + eliminar ──────────────────────────────────────


async def test_editar_evento(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    inicia = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()
    creada = (
        await client.post(
            "/api/v1/eventos",
            json={"titulo": "_test_ev_editar", "inicia_en": inicia},
        )
    ).json()
    eid = creada["id"]
    try:
        r = await ejecutar_tool(
            _fresh_db,
            "editar_evento",
            {"evento_id": eid, "ubicacion": "Aula 3", "titulo": "Renombrado"},
        )
        assert r["ok"], r
        actual = (await client.get(f"/api/v1/eventos/{eid}")).json()
        assert actual["titulo"] == "Renombrado"
        assert actual["ubicacion"] == "Aula 3"
    finally:
        await client.delete(f"/api/v1/eventos/{eid}/permanente")


async def test_eliminar_evento_es_reversible(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    inicia = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()
    creada = (
        await client.post(
            "/api/v1/eventos",
            json={"titulo": "_test_ev_eliminar", "inicia_en": inicia},
        )
    ).json()
    eid = creada["id"]
    try:
        r = await ejecutar_tool(
            _fresh_db, "eliminar_evento", {"evento_id": eid}
        )
        assert r["ok"], r
        actual = (await client.get(f"/api/v1/eventos/{eid}")).json()
        assert actual["eliminado_en"] is not None
    finally:
        await client.delete(f"/api/v1/eventos/{eid}/permanente")


# ── apuntes: editar + eliminar ──────────────────────────────────────


async def test_editar_apunte_anexa_contenido(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    creada = (
        await client.post(
            "/api/v1/apuntes",
            json={"titulo": "_test_ap_editar", "contenido": "original"},
        )
    ).json()
    aid = creada["id"]
    try:
        r = await ejecutar_tool(
            _fresh_db,
            "editar_apunte",
            {
                "apunte_id": aid,
                "contenido": "original\n\nañadido",
                "etiquetas": ["test", "capa2"],
            },
        )
        assert r["ok"], r
        actual = (await client.get(f"/api/v1/apuntes/{aid}")).json()
        assert "añadido" in actual["contenido"]
        assert "capa2" in actual["etiquetas"]
    finally:
        await client.delete(f"/api/v1/apuntes/{aid}/permanente")


async def test_eliminar_apunte_es_reversible(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    creada = (
        await client.post(
            "/api/v1/apuntes",
            json={"titulo": "_test_ap_elim", "contenido": "x"},
        )
    ).json()
    aid = creada["id"]
    try:
        r = await ejecutar_tool(
            _fresh_db, "eliminar_apunte", {"apunte_id": aid}
        )
        assert r["ok"], r
        actual = (await client.get(f"/api/v1/apuntes/{aid}")).json()
        assert actual["eliminado_en"] is not None
    finally:
        await client.delete(f"/api/v1/apuntes/{aid}/permanente")


# ── proyectos: crear + editar + cambios de estado + tope ────────────


async def test_crear_proyecto_aparcado_no_aplica_tope(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    r = await ejecutar_tool(
        _fresh_db,
        "crear_proyecto",
        {"nombre": "_test_proy_aparcado", "estado": "aparcado"},
    )
    assert r["ok"], r
    pid = r["datos"]["id"]
    try:
        assert r["datos"]["estado"] == "aparcado"
    finally:
        await client.delete(f"/api/v1/proyectos/{pid}")


async def test_crear_proyecto_activo_respeta_tope(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    # Asume que el seed deja ≤3 activos. Si ya hay 3, debe fallar.
    activos_actuales = [
        p
        for p in (await client.get("/api/v1/proyectos")).json()
        if p["estado"] == "activo"
    ]
    creados: list[str] = []
    try:
        # Llenar hasta 3
        while len(activos_actuales) + len(creados) < 3:
            r = await ejecutar_tool(
                _fresh_db,
                "crear_proyecto",
                {"nombre": f"_test_relleno_{len(creados)}", "estado": "activo"},
            )
            assert r["ok"], r
            creados.append(r["datos"]["id"])
        # El cuarto debe fallar con tipo `tope_proyectos`
        r = await ejecutar_tool(
            _fresh_db,
            "crear_proyecto",
            {"nombre": "_test_cuarto", "estado": "activo"},
        )
        assert r["ok"] is False
        assert r["tipo"] == "tope_proyectos"
    finally:
        for pid in creados:
            await client.delete(f"/api/v1/proyectos/{pid}")


async def test_aparcar_y_reactivar_proyecto(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    # Creamos un proyecto en estado aparcado para no chocar con tope
    r = await ejecutar_tool(
        _fresh_db,
        "crear_proyecto",
        {"nombre": "_test_aparcar_reactivar", "estado": "aparcado"},
    )
    assert r["ok"]
    pid = r["datos"]["id"]
    try:
        # Ya está aparcado: aparcar es idempotente
        r = await ejecutar_tool(
            _fresh_db, "aparcar_proyecto", {"proyecto_id": pid}
        )
        assert r["ok"], r
        assert r["datos"]["estado"] == "aparcado"

        # Reactivar: si hay 3 activos, falla con tope; si no, debe pasar
        activos = [
            p
            for p in (await client.get("/api/v1/proyectos")).json()
            if p["estado"] == "activo" and p["id"] != pid
        ]
        r = await ejecutar_tool(
            _fresh_db, "reactivar_proyecto", {"proyecto_id": pid}
        )
        if len(activos) >= 3:
            assert r["ok"] is False
            assert r["tipo"] == "tope_proyectos"
        else:
            assert r["ok"], r
            assert r["datos"]["estado"] == "activo"
    finally:
        await client.delete(f"/api/v1/proyectos/{pid}")


async def test_terminar_proyecto(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    r = await ejecutar_tool(
        _fresh_db,
        "crear_proyecto",
        {"nombre": "_test_terminar", "estado": "aparcado"},
    )
    pid = r["datos"]["id"]
    try:
        r = await ejecutar_tool(
            _fresh_db, "terminar_proyecto", {"proyecto_id": pid}
        )
        assert r["ok"], r
        assert r["datos"]["estado"] == "terminado"
        actual = (await client.get(f"/api/v1/proyectos/{pid}")).json()
        assert actual["estado"] == "terminado"
        assert actual["inactivo_desde"] is not None
    finally:
        await client.delete(f"/api/v1/proyectos/{pid}")


async def test_editar_proyecto_no_permite_cambiar_estado(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    r = await ejecutar_tool(
        _fresh_db,
        "crear_proyecto",
        {"nombre": "_test_editar_proy", "estado": "aparcado"},
    )
    pid = r["datos"]["id"]
    try:
        r = await ejecutar_tool(
            _fresh_db,
            "editar_proyecto",
            {"proyecto_id": pid, "estado": "activo"},
        )
        assert r["ok"] is False
        assert r["tipo"] == "validacion"

        # Editar otros campos sí funciona
        r = await ejecutar_tool(
            _fresh_db,
            "editar_proyecto",
            {"proyecto_id": pid, "linea_meta": "criterio claro"},
        )
        assert r["ok"], r
    finally:
        await client.delete(f"/api/v1/proyectos/{pid}")


# ── reabrir_tarea (el ya existente, pero lo verificamos) ────────────


async def test_reabrir_tarea(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    creada = (
        await client.post(
            "/api/v1/tareas", json={"titulo": "_test_reabrir"}
        )
    ).json()
    tid = creada["id"]
    try:
        # Completarla
        r = await ejecutar_tool(
            _fresh_db, "completar_tarea", {"tarea_id": tid}
        )
        assert r["ok"]
        # Reabrirla
        r = await ejecutar_tool(
            _fresh_db, "reabrir_tarea", {"tarea_id": tid}
        )
        assert r["ok"], r
        actual = (await client.get(f"/api/v1/tareas/{tid}")).json()
        assert actual["completada"] is False
        assert actual["completada_en"] is None
    finally:
        await client.delete(f"/api/v1/tareas/{tid}/permanente")
