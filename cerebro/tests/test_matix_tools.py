"""Tests del dispatcher de tools de Matix.

No probamos el modelo (OpenAI) — eso es no-determinista y caro. Sí
probamos `ejecutar_tool` end-to-end contra Supabase real: que cada
herramienta cree/modifique lo que debe, y que los errores
esperables devuelvan `ok: False` con `tipo` correcto en vez de
explotar.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import uuid4

from httpx import AsyncClient

from app.db import Postgrest
from app.matix.tools import TABLAS_AFECTADAS, TOOL_DEFINITIONS, ejecutar_tool


# ── Sanity de los schemas ────────────────────────────────────────────


def test_tool_definitions_y_handlers_alineados() -> None:
    """Cada tool que el modelo ve debe tener un handler. Cada handler
    debe declarar qué tablas modifica."""
    nombres_def = {t["function"]["name"] for t in TOOL_DEFINITIONS}
    # ejecutar_tool tiene _HANDLERS interno; lo testeamos indirectamente
    # cruzando con TABLAS_AFECTADAS, que es público.
    assert nombres_def == set(TABLAS_AFECTADAS.keys())


async def test_handler_desconocido_devuelve_error_estructurado(
    _fresh_db: Postgrest,
) -> None:
    r = await ejecutar_tool(_fresh_db, "no_existe", {})
    assert r["ok"] is False
    assert r["tipo"] == "desconocida"


# ── crear_tarea ─────────────────────────────────────────────────────


async def test_crear_tarea_minima(_fresh_db: Postgrest, client: AsyncClient) -> None:
    r = await ejecutar_tool(
        _fresh_db, "crear_tarea", {"titulo": "_test_tool_crear_tarea"}
    )
    assert r["ok"], r
    tid = r["datos"]["id"]
    try:
        # Verificamos contra el endpoint HTTP que la tarea quedó en BD
        got = await client.get(f"/api/v1/tareas/{tid}")
        assert got.status_code == 200
        assert got.json()["titulo"] == "_test_tool_crear_tarea"
    finally:
        await client.delete(f"/api/v1/tareas/{tid}/permanente")


async def test_crear_tarea_validacion_titulo_vacio(_fresh_db: Postgrest) -> None:
    r = await ejecutar_tool(_fresh_db, "crear_tarea", {"titulo": ""})
    assert r["ok"] is False
    assert r["tipo"] == "validacion"


# ── completar_tarea ─────────────────────────────────────────────────


async def test_completar_tarea(_fresh_db: Postgrest, client: AsyncClient) -> None:
    # Creamos una tarea vía HTTP, después la completamos con la tool
    creada = (
        await client.post(
            "/api/v1/tareas",
            json={"titulo": "_test_tool_completar"},
        )
    ).json()
    tid = creada["id"]
    try:
        r = await ejecutar_tool(_fresh_db, "completar_tarea", {"tarea_id": tid})
        assert r["ok"], r
        # Verificamos que la BD refleja completada=True
        got = (await client.get(f"/api/v1/tareas/{tid}")).json()
        assert got["completada"] is True
        assert got["completada_en"] is not None
    finally:
        await client.delete(f"/api/v1/tareas/{tid}/permanente")


async def test_completar_tarea_inexistente(_fresh_db: Postgrest) -> None:
    r = await ejecutar_tool(
        _fresh_db,
        "completar_tarea",
        {"tarea_id": str(uuid4())},
    )
    assert r["ok"] is False
    assert r["tipo"] == "no_existe"


async def test_completar_tarea_id_no_uuid(_fresh_db: Postgrest) -> None:
    r = await ejecutar_tool(
        _fresh_db, "completar_tarea", {"tarea_id": "no-soy-uuid"}
    )
    assert r["ok"] is False
    assert r["tipo"] == "validacion"


# ── reabrir_tarea ───────────────────────────────────────────────────


async def test_reabrir_tarea_deshace_completar(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    # Crear → completar → reabrir → debe quedar pendiente.
    creada = (
        await client.post(
            "/api/v1/tareas",
            json={"titulo": "_test_tool_reabrir"},
        )
    ).json()
    tid = creada["id"]
    try:
        # Completar
        r1 = await ejecutar_tool(
            _fresh_db, "completar_tarea", {"tarea_id": tid}
        )
        assert r1["ok"]
        assert (await client.get(f"/api/v1/tareas/{tid}")).json()[
            "completada"
        ] is True

        # Reabrir
        r2 = await ejecutar_tool(
            _fresh_db, "reabrir_tarea", {"tarea_id": tid}
        )
        assert r2["ok"], r2
        got = (await client.get(f"/api/v1/tareas/{tid}")).json()
        assert got["completada"] is False
        assert got["completada_en"] is None
    finally:
        await client.delete(f"/api/v1/tareas/{tid}/permanente")


async def test_reabrir_tarea_ya_pendiente(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    creada = (
        await client.post(
            "/api/v1/tareas",
            json={"titulo": "_test_tool_reabrir_idemp"},
        )
    ).json()
    tid = creada["id"]
    try:
        r = await ejecutar_tool(
            _fresh_db, "reabrir_tarea", {"tarea_id": tid}
        )
        # No falla: marca que ya estaba pendiente.
        assert r["ok"], r
        assert r["datos"].get("ya_estaba_pendiente") is True
    finally:
        await client.delete(f"/api/v1/tareas/{tid}/permanente")


async def test_reabrir_tarea_inexistente(_fresh_db: Postgrest) -> None:
    r = await ejecutar_tool(
        _fresh_db,
        "reabrir_tarea",
        {"tarea_id": str(uuid4())},
    )
    assert r["ok"] is False
    assert r["tipo"] == "no_existe"


# ── crear_evento ────────────────────────────────────────────────────


async def test_crear_evento(_fresh_db: Postgrest, client: AsyncClient) -> None:
    inicia = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()
    r = await ejecutar_tool(
        _fresh_db,
        "crear_evento",
        {"titulo": "_test_tool_evento", "inicia_en": inicia},
    )
    assert r["ok"], r
    eid = r["datos"]["id"]
    try:
        got = (await client.get(f"/api/v1/eventos/{eid}")).json()
        assert got["titulo"] == "_test_tool_evento"
    finally:
        await client.delete(f"/api/v1/eventos/{eid}/permanente")


# ── crear_apunte ────────────────────────────────────────────────────


async def test_crear_apunte(_fresh_db: Postgrest, client: AsyncClient) -> None:
    r = await ejecutar_tool(
        _fresh_db,
        "crear_apunte",
        {
            "titulo": "_test_tool_apunte",
            "contenido": "hola",
            "etiquetas": ["test"],
        },
    )
    assert r["ok"], r
    aid = r["datos"]["id"]
    try:
        got = (await client.get(f"/api/v1/apuntes/{aid}")).json()
        assert got["titulo"] == "_test_tool_apunte"
        assert "test" in got["etiquetas"]
    finally:
        await client.delete(f"/api/v1/apuntes/{aid}/permanente")


# ── registrar_cierre ────────────────────────────────────────────────


async def test_registrar_cierre_crea_y_sobreescribe(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    # Fecha que no se solape con otro test: muy atrás
    fecha = "1990-01-02"
    r1 = await ejecutar_tool(
        _fresh_db,
        "registrar_cierre",
        {"items": ["a", "b", "c"], "fecha": fecha},
    )
    assert r1["ok"], r1
    cid = r1["datos"]["id"]
    assert r1["datos"]["sobreescrito"] is False

    try:
        # Segunda llamada: actualiza el mismo cierre
        r2 = await ejecutar_tool(
            _fresh_db,
            "registrar_cierre",
            {"items": ["x"], "fecha": fecha, "nota_extra": "rehecho"},
        )
        assert r2["ok"], r2
        assert r2["datos"]["sobreescrito"] is True
        # Mismo id que el original
        assert r2["datos"]["id"] == cid
    finally:
        await client.delete(f"/api/v1/cierres_dia/{cid}")


async def test_registrar_cierre_fecha_invalida(_fresh_db: Postgrest) -> None:
    r = await ejecutar_tool(
        _fresh_db,
        "registrar_cierre",
        {"items": ["a"], "fecha": "no-es-fecha"},
    )
    assert r["ok"] is False
    assert r["tipo"] == "validacion"


# ── marcar_accion_siguiente_hecha ───────────────────────────────────


async def test_marcar_accion_siguiente_hecha(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    # Setup: tarea libre + proyecto que la apunta como acción siguiente.
    tarea = (
        await client.post(
            "/api/v1/tareas",
            json={"titulo": "_test_tool_acc_sig"},
        )
    ).json()
    tid = tarea["id"]

    # Aparcamos uno activo para liberar cupo si hace falta (el test
    # también puede correr en una BD con 3 activos). Estrategia: si
    # nos da 409, creamos el proyecto como "aparcado" para no chocar
    # con el tope.
    crear = await client.post(
        "/api/v1/proyectos",
        json={
            "nombre": "_test_tool_acc_sig_proyecto",
            "estado": "aparcado",
            "tarea_siguiente_id": tid,
        },
    )
    assert crear.status_code == 201, crear.text
    pid = crear.json()["id"]

    try:
        r = await ejecutar_tool(
            _fresh_db, "marcar_accion_siguiente_hecha", {"proyecto_id": pid}
        )
        assert r["ok"], r
        # Tarea debe estar completada
        got_t = (await client.get(f"/api/v1/tareas/{tid}")).json()
        assert got_t["completada"] is True
        # Proyecto debe tener tarea_siguiente_id en null
        got_p = (await client.get(f"/api/v1/proyectos/{pid}")).json()
        assert got_p["tarea_siguiente_id"] is None
    finally:
        await client.delete(f"/api/v1/proyectos/{pid}")
        await client.delete(f"/api/v1/tareas/{tid}/permanente")


async def test_accion_siguiente_sin_definir(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    # Proyecto aparcado sin acción siguiente
    crear = await client.post(
        "/api/v1/proyectos",
        json={
            "nombre": "_test_tool_acc_sig_vacia",
            "estado": "aparcado",
        },
    )
    pid = crear.json()["id"]
    try:
        r = await ejecutar_tool(
            _fresh_db, "marcar_accion_siguiente_hecha", {"proyecto_id": pid}
        )
        assert r["ok"] is False
        assert r["tipo"] == "sin_accion_siguiente"
    finally:
        await client.delete(f"/api/v1/proyectos/{pid}")
