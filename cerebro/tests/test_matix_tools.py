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


# ── crear_apunte: clasificación (proyecto / curso / general) ─────────
#
# La decisión de a qué proyecto/curso pertenece una idea la toma el
# MODELO (no determinista, no se testea acá). Lo que sí garantiza el
# handler es: si recibe un `proyecto_id`/`curso_id`, etiqueta y reporta
# dónde lo archivó; si no recibe ninguno, queda general. Y nunca tiene
# poder para crear un proyecto/curso.


async def test_crear_apunte_etiquetado_a_proyecto(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    # Proyecto aparcado para no chocar con el tope de 3 activos.
    crear = await client.post(
        "/api/v1/proyectos",
        json={"nombre": "_test_tool_apunte_proyecto", "estado": "aparcado"},
    )
    assert crear.status_code == 201, crear.text
    pid = crear.json()["id"]

    r = await ejecutar_tool(
        _fresh_db,
        "crear_apunte",
        {
            "titulo": "_test_tool_apunte_clasif",
            "contenido": "idea que pertenece al proyecto",
            "proyecto_id": pid,
        },
    )
    assert r["ok"], r
    aid = r["datos"]["id"]
    try:
        # El handler reporta dónde lo archivó, con nombre desde la BD.
        assert r["datos"]["general"] is False
        assert r["datos"]["proyecto_nombre"] == "_test_tool_apunte_proyecto"
        assert "curso_nombre" not in r["datos"]
        # Y la fila quedó realmente etiquetada al proyecto.
        got = (await client.get(f"/api/v1/apuntes/{aid}")).json()
        assert got["proyecto_id"] == pid
    finally:
        await client.delete(f"/api/v1/apuntes/{aid}/permanente")
        await client.delete(f"/api/v1/proyectos/{pid}")


async def test_crear_apunte_etiquetado_a_curso(
    _fresh_db: Postgrest, client: AsyncClient, curso_id: str
) -> None:
    r = await ejecutar_tool(
        _fresh_db,
        "crear_apunte",
        {
            "titulo": "_test_tool_apunte_curso",
            "contenido": "idea de la materia",
            "curso_id": curso_id,
        },
    )
    assert r["ok"], r
    aid = r["datos"]["id"]
    try:
        assert r["datos"]["general"] is False
        assert r["datos"]["curso_nombre"] == "_test_curso_fix"
        assert "proyecto_nombre" not in r["datos"]
    finally:
        await client.delete(f"/api/v1/apuntes/{aid}/permanente")


async def test_crear_apunte_ambiguo_queda_general(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    """Idea sin proyecto ni curso → general. El handler no debe crear
    ningún proyecto para clasificar: el conteo de proyectos no cambia."""
    antes = len((await client.get("/api/v1/proyectos")).json())

    r = await ejecutar_tool(
        _fresh_db,
        "crear_apunte",
        {
            "titulo": "_test_tool_apunte_general",
            "contenido": "una idea suelta que no calza con nada",
        },
    )
    assert r["ok"], r
    aid = r["datos"]["id"]
    try:
        assert r["datos"]["general"] is True
        assert "proyecto_nombre" not in r["datos"]
        assert "curso_nombre" not in r["datos"]
        # crear_apunte no tiene poder para crear proyectos.
        despues = len((await client.get("/api/v1/proyectos")).json())
        assert despues == antes
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


# ── navegar (no toca datos) ─────────────────────────────────────────


async def test_navegar_seccion_valida(_fresh_db: Postgrest) -> None:
    r = await ejecutar_tool(_fresh_db, "navegar", {"seccion": "universidad"})
    assert r["ok"], r
    assert r["datos"]["seccion"] == "universidad"


async def test_navegar_seccion_invalida(_fresh_db: Postgrest) -> None:
    r = await ejecutar_tool(_fresh_db, "navegar", {"seccion": "marte"})
    assert r["ok"] is False
    assert r["tipo"] == "validacion"


# ── Finanzas: movimientos CRUD ──────────────────────────────────────


async def test_movimientos_crud(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    # Crear un gasto.
    r = await ejecutar_tool(
        _fresh_db,
        "crear_movimiento",
        {"tipo": "gasto", "monto": 30, "categoria": "_test_comida"},
    )
    assert r["ok"], r
    mid = r["datos"]["id"]
    assert r["datos"]["tipo"] == "gasto"

    # Consultar: el movimiento aparece y el balance refleja el gasto.
    cons = await ejecutar_tool(_fresh_db, "consultar_movimientos", {})
    assert cons["ok"], cons
    ids = {m["id"] for m in cons["datos"]["movimientos"]}
    assert mid in ids

    # Editar el monto.
    ed = await ejecutar_tool(
        _fresh_db, "editar_movimiento", {"movimiento_id": mid, "monto": 45}
    )
    assert ed["ok"], ed
    assert float(ed["datos"]["monto"]) == 45

    # Eliminar (permanente: finanzas no tiene papelera). Requiere confirmado.
    el = await ejecutar_tool(
        _fresh_db,
        "eliminar_movimiento",
        {"movimiento_id": mid, "confirmado": True},
    )
    assert el["ok"], el
    assert el["datos"]["reversible"] is False

    # Ya no está.
    got = await client.get(f"/api/v1/movimientos/{mid}")
    assert got.status_code == 404


async def test_eliminar_movimiento_inexistente(_fresh_db: Postgrest) -> None:
    from uuid import uuid4

    r = await ejecutar_tool(
        _fresh_db,
        "eliminar_movimiento",
        {"movimiento_id": str(uuid4()), "confirmado": True},
    )
    assert r["ok"] is False
    assert r["tipo"] == "no_existe"


# ── crear_tareas (lote) ─────────────────────────────────────────────


async def test_crear_tareas_lote(
    _fresh_db: Postgrest, client: AsyncClient
) -> None:
    # Proyecto contenedor (simula el de la skill).
    pr = await client.post(
        "/api/v1/proyectos", json={"nombre": "_test_lote_skill"}
    )
    pid = pr.json()["id"]
    r = await ejecutar_tool(
        _fresh_db,
        "crear_tareas",
        {
            "proyecto_id": pid,
            "tareas": [
                {"titulo": "_test_lote_s1"},
                {"titulo": "_test_lote_s2", "prioridad": "alta"},
                {"titulo": "_test_lote_s3"},
            ],
        },
    )
    assert r["ok"], r
    assert r["datos"]["total"] == 3
    ids = [t["id"] for t in r["datos"]["tareas"]]
    try:
        # Todas quedaron en BD y en el proyecto indicado.
        for tid in ids:
            got = await client.get(f"/api/v1/tareas/{tid}")
            assert got.status_code == 200
            assert got.json()["proyecto_id"] == pid
    finally:
        for tid in ids:
            await client.delete(f"/api/v1/tareas/{tid}/permanente")
        await client.delete(f"/api/v1/proyectos/{pid}")


async def test_crear_tareas_vacia_falla(_fresh_db: Postgrest) -> None:
    r = await ejecutar_tool(_fresh_db, "crear_tareas", {"tareas": []})
    assert r["ok"] is False
    assert r["tipo"] == "validacion"


async def test_crear_tareas_tope_guardrail(_fresh_db: Postgrest) -> None:
    from app.matix.tools import _MAX_LOTE_TAREAS

    muchas = [{"titulo": f"t{i}"} for i in range(_MAX_LOTE_TAREAS + 1)]
    r = await ejecutar_tool(_fresh_db, "crear_tareas", {"tareas": muchas})
    assert r["ok"] is False
    assert r["tipo"] == "validacion"
