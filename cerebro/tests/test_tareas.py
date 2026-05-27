"""CRUD de `tareas` end-to-end contra Supabase."""
from __future__ import annotations

from httpx import AsyncClient


async def test_auth_requerida(client_anon: AsyncClient) -> None:
    r = await client_anon.get("/api/v1/tareas")
    assert r.status_code == 401


async def test_auth_invalida(client_anon: AsyncClient) -> None:
    r = await client_anon.get("/api/v1/tareas", headers={"X-Matix-Key": "no-es-la-correcta"})
    assert r.status_code == 401


async def test_crud_tarea_ciclo_completo(client: AsyncClient) -> None:
    # Crear
    body = {
        "titulo": "_test_ciclo_tareas",
        "nota": "creada por pytest",
        "prioridad": "alta",
    }
    r = await client.post("/api/v1/tareas", json=body)
    assert r.status_code == 201, r.text
    creada = r.json()
    tarea_id = creada["id"]

    try:
        assert creada["titulo"] == body["titulo"]
        assert creada["prioridad"] == "alta"
        assert creada["completada"] is False
        assert creada["completada_en"] is None
        assert creada["creada_en"]
        assert creada["actualizada_en"]

        # Leer por id
        r = await client.get(f"/api/v1/tareas/{tarea_id}")
        assert r.status_code == 200
        assert r.json()["id"] == tarea_id

        # Listar (la nueva tarea debe aparecer)
        r = await client.get("/api/v1/tareas")
        assert r.status_code == 200
        ids = [t["id"] for t in r.json()]
        assert tarea_id in ids

        # Actualizar: marcar como completada y cambiar prioridad
        r = await client.patch(
            f"/api/v1/tareas/{tarea_id}",
            json={"completada": True, "prioridad": "baja"},
        )
        assert r.status_code == 200, r.text
        actualizada = r.json()
        assert actualizada["completada"] is True
        assert actualizada["prioridad"] == "baja"
        # El trigger debe haber tocado `actualizada_en`
        assert actualizada["actualizada_en"] >= creada["actualizada_en"]
    finally:
        # Limpiar siempre. Con Capa 2 Paso 5, DELETE es soft, así que
        # purgamos con /permanente para no dejar basura en la papelera
        # del test. /permanente es 404-tolerante si ya no existe.
        await client.delete(f"/api/v1/tareas/{tarea_id}")
        r = await client.delete(f"/api/v1/tareas/{tarea_id}/permanente")
        assert r.status_code in (204, 404)

    # Confirmar borrado: la tarea ya no aparece ni en la lista normal
    # ni con un GET directo (purgada).
    r = await client.get(f"/api/v1/tareas/{tarea_id}")
    assert r.status_code == 404


async def test_get_inexistente_devuelve_404(client: AsyncClient) -> None:
    r = await client.get("/api/v1/tareas/00000000-0000-0000-0000-000000000000")
    assert r.status_code == 404


async def test_patch_inexistente_devuelve_404(client: AsyncClient) -> None:
    r = await client.patch(
        "/api/v1/tareas/00000000-0000-0000-0000-000000000000",
        json={"titulo": "no existe"},
    )
    assert r.status_code == 404


async def test_delete_inexistente_devuelve_404(client: AsyncClient) -> None:
    r = await client.delete("/api/v1/tareas/00000000-0000-0000-0000-000000000000")
    assert r.status_code == 404


async def test_post_titulo_vacio_devuelve_422(client: AsyncClient) -> None:
    r = await client.post("/api/v1/tareas", json={"titulo": ""})
    assert r.status_code == 422


async def test_post_prioridad_invalida_devuelve_422(client: AsyncClient) -> None:
    r = await client.post(
        "/api/v1/tareas",
        json={"titulo": "_test_prio", "prioridad": "urgentisima"},
    )
    assert r.status_code == 422
