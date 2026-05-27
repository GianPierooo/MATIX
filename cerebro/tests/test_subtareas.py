from __future__ import annotations

from httpx import AsyncClient


async def test_crud_subtarea_ciclo_completo(client: AsyncClient, tarea_id: str) -> None:
    r = await client.post(
        "/api/v1/subtareas",
        json={"tarea_id": tarea_id, "titulo": "_test_subt", "orden": 1},
    )
    assert r.status_code == 201, r.text
    creada = r.json()
    sid = creada["id"]

    try:
        assert creada["tarea_id"] == tarea_id
        assert creada["completada"] is False

        r = await client.get(f"/api/v1/subtareas/{sid}")
        assert r.status_code == 200

        r = await client.get("/api/v1/subtareas")
        assert r.status_code == 200
        assert sid in [s["id"] for s in r.json()]

        r = await client.patch(f"/api/v1/subtareas/{sid}", json={"completada": True})
        assert r.status_code == 200
        assert r.json()["completada"] is True
    finally:
        r = await client.delete(f"/api/v1/subtareas/{sid}")
        assert r.status_code in (204, 404)


async def test_listar_filtrado_por_tarea_id(
    client: AsyncClient, tarea_id: str
) -> None:
    """El query param `tarea_id` filtra el listado a las subtareas de
    esa tarea (no devuelve las de otras)."""
    # Una subtarea de NUESTRA tarea
    r = await client.post(
        "/api/v1/subtareas",
        json={"tarea_id": tarea_id, "titulo": "_test_filtro_mia"},
    )
    assert r.status_code == 201
    sid_mia = r.json()["id"]

    # Otra tarea con su propia subtarea, para asegurar que NO aparece
    r = await client.post("/api/v1/tareas", json={"titulo": "_test_otra"})
    assert r.status_code == 201
    otra_tid = r.json()["id"]
    r = await client.post(
        "/api/v1/subtareas",
        json={"tarea_id": otra_tid, "titulo": "_test_filtro_otra"},
    )
    assert r.status_code == 201
    sid_otra = r.json()["id"]

    try:
        r = await client.get(f"/api/v1/subtareas?tarea_id={tarea_id}")
        assert r.status_code == 200
        ids = [s["id"] for s in r.json()]
        assert sid_mia in ids
        assert sid_otra not in ids
    finally:
        await client.delete(f"/api/v1/subtareas/{sid_mia}")
        await client.delete(f"/api/v1/subtareas/{sid_otra}")
        await client.delete(f"/api/v1/tareas/{otra_tid}")


async def test_borrado_suave_no_destruye_subtareas(
    client: AsyncClient,
) -> None:
    """Con la papelera (Capa 2 Paso 5), DELETE en tarea es SOFT, así
    que la subtarea queda viva (el padre solo está marcado con
    `eliminado_en`). Esto importa para restaurar después: si la
    cascade hubiera disparado, la restauración traería un padre sin
    hijas."""
    r = await client.post(
        "/api/v1/tareas", json={"titulo": "_test_padre_soft"}
    )
    tid = r.json()["id"]
    r = await client.post(
        "/api/v1/subtareas", json={"tarea_id": tid, "titulo": "_test_hija_soft"}
    )
    sid = r.json()["id"]
    try:
        # Borrar suave la tarea padre
        r = await client.delete(f"/api/v1/tareas/{tid}")
        assert r.status_code == 204

        # La subtarea sigue existiendo
        r = await client.get(f"/api/v1/subtareas/{sid}")
        assert r.status_code == 200
    finally:
        # Borrar permanente: ahora SÍ debería disparar la cascade.
        await client.delete(f"/api/v1/tareas/{tid}/permanente")
        r = await client.get(f"/api/v1/subtareas/{sid}")
        assert r.status_code == 404


async def test_borrado_permanente_cascade_subtareas(
    client: AsyncClient,
) -> None:
    """Borrar permanente (vaciar papelera) destruye también las
    subtareas, vía la FK ON DELETE CASCADE."""
    r = await client.post(
        "/api/v1/tareas", json={"titulo": "_test_padre_purga"}
    )
    tid = r.json()["id"]
    r = await client.post(
        "/api/v1/subtareas",
        json={"tarea_id": tid, "titulo": "_test_hija_purga"},
    )
    sid = r.json()["id"]

    # Soft luego permanente
    await client.delete(f"/api/v1/tareas/{tid}")
    r = await client.delete(f"/api/v1/tareas/{tid}/permanente")
    assert r.status_code == 204
    r = await client.get(f"/api/v1/subtareas/{sid}")
    assert r.status_code == 404
