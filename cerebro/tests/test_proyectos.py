"""CRUD de `proyectos` end-to-end + reglas del Documento Maestro.

Reglas que se prueban aquí:
- Tope de 3 activos en POST y al reactivar.
- Coherencia acción siguiente ↔ proyecto (tarea ya en otro proyecto → 409,
  tarea inexistente → 422, tarea libre → 201).
- `inactivo_desde` se fija al aparcar/terminar y se limpia al reactivar.
- `ultima_actividad_en` se refresca en cada PATCH.

Algunos tests requieren controlar cuántos proyectos activos hay en la
BD; usan `_aparcar_originales` para vaciar el "estado" antes y
`_reactivar` para restaurarlo al final.
"""
from __future__ import annotations

import asyncio

from httpx import AsyncClient

NIL_UUID = "00000000-0000-0000-0000-000000000000"


# ----------------------------- helpers ------------------------------------


async def _listar(client: AsyncClient) -> list[dict]:
    r = await client.get("/api/v1/proyectos")
    assert r.status_code == 200, r.text
    return r.json()


async def _aparcar_originales(client: AsyncClient) -> list[str]:
    """Aparca todos los proyectos activos que había antes del test y
    devuelve sus ids para poder reactivarlos en el cleanup.
    """
    aparcados: list[str] = []
    for p in await _listar(client):
        if p["estado"] == "activo":
            r = await client.patch(
                f"/api/v1/proyectos/{p['id']}", json={"estado": "aparcado"}
            )
            assert r.status_code == 200, r.text
            aparcados.append(p["id"])
    return aparcados


async def _reactivar(client: AsyncClient, ids: list[str]) -> None:
    for pid in ids:
        await client.patch(f"/api/v1/proyectos/{pid}", json={"estado": "activo"})


async def _borrar(client: AsyncClient, ids: list[str]) -> None:
    for pid in ids:
        await client.delete(f"/api/v1/proyectos/{pid}")


# ----------------------------- auth ---------------------------------------


async def test_auth_requerida(client_anon: AsyncClient) -> None:
    r = await client_anon.get("/api/v1/proyectos")
    assert r.status_code == 401


async def test_auth_invalida(client_anon: AsyncClient) -> None:
    r = await client_anon.get(
        "/api/v1/proyectos", headers={"X-Matix-Key": "no-es-la-correcta"}
    )
    assert r.status_code == 401


# ----------------------------- CRUD ---------------------------------------


async def test_crud_proyecto_ciclo_completo(client: AsyncClient) -> None:
    # Para no chocar con el tope, creamos como "aparcado".
    body = {
        "nombre": "_test_ciclo_proyectos",
        "descripcion": "creado por pytest",
        "estado": "aparcado",
        "linea_meta": "demostrar el ciclo",
        "color": "#2D7FF9",
    }
    r = await client.post("/api/v1/proyectos", json=body)
    assert r.status_code == 201, r.text
    creado = r.json()
    pid = creado["id"]

    try:
        assert creado["nombre"] == body["nombre"]
        assert creado["estado"] == "aparcado"
        assert creado["linea_meta"] == "demostrar el ciclo"
        assert creado["ultima_actividad_en"]
        assert creado["creado_en"]

        # Leer por id
        r = await client.get(f"/api/v1/proyectos/{pid}")
        assert r.status_code == 200
        assert r.json()["id"] == pid

        # Listar (el nuevo proyecto debe aparecer)
        ids = [p["id"] for p in await _listar(client)]
        assert pid in ids

        # PATCH parcial: cambiar descripción
        r = await client.patch(
            f"/api/v1/proyectos/{pid}",
            json={"descripcion": "editada por pytest"},
        )
        assert r.status_code == 200, r.text
        editado = r.json()
        assert editado["descripcion"] == "editada por pytest"
        assert editado["actualizado_en"] >= creado["actualizado_en"]
    finally:
        r = await client.delete(f"/api/v1/proyectos/{pid}")
        assert r.status_code in (204, 404)

    r = await client.get(f"/api/v1/proyectos/{pid}")
    assert r.status_code == 404


async def test_get_inexistente_devuelve_404(client: AsyncClient) -> None:
    r = await client.get(f"/api/v1/proyectos/{NIL_UUID}")
    assert r.status_code == 404


async def test_patch_inexistente_devuelve_404(client: AsyncClient) -> None:
    r = await client.patch(
        f"/api/v1/proyectos/{NIL_UUID}", json={"nombre": "no existe"}
    )
    assert r.status_code == 404


async def test_delete_inexistente_devuelve_404(client: AsyncClient) -> None:
    r = await client.delete(f"/api/v1/proyectos/{NIL_UUID}")
    assert r.status_code == 404


# ----------------------------- 422 ----------------------------------------


async def test_post_nombre_vacio_devuelve_422(client: AsyncClient) -> None:
    r = await client.post(
        "/api/v1/proyectos", json={"nombre": "", "estado": "aparcado"}
    )
    assert r.status_code == 422


async def test_post_estado_invalido_devuelve_422(client: AsyncClient) -> None:
    r = await client.post(
        "/api/v1/proyectos",
        json={"nombre": "_test_estado_malo", "estado": "vivo"},
    )
    assert r.status_code == 422


async def test_post_prioridad_fuera_de_rango_devuelve_422(
    client: AsyncClient,
) -> None:
    r = await client.post(
        "/api/v1/proyectos",
        json={"nombre": "_test_prio_malo", "estado": "aparcado", "prioridad": 5},
    )
    assert r.status_code == 422


# ----------------------------- tope de 3 ----------------------------------


async def test_tope_de_3_activos(client: AsyncClient) -> None:
    originales = await _aparcar_originales(client)
    creados: list[str] = []
    try:
        # 3 activos: OK
        for i in (1, 2, 3):
            r = await client.post(
                "/api/v1/proyectos",
                json={"nombre": f"_test_tope_{i}", "prioridad": i},
            )
            assert r.status_code == 201, r.text
            creados.append(r.json()["id"])

        # 4to activo: 409
        r = await client.post(
            "/api/v1/proyectos", json={"nombre": "_test_tope_4"}
        )
        assert r.status_code == 409, r.text
        assert "3 proyectos activos" in r.json()["detail"]

        # Aparcar uno libera espacio para el cuarto
        r = await client.patch(
            f"/api/v1/proyectos/{creados[0]}", json={"estado": "aparcado"}
        )
        assert r.status_code == 200

        r = await client.post(
            "/api/v1/proyectos", json={"nombre": "_test_tope_4"}
        )
        assert r.status_code == 201, r.text
        creados.append(r.json()["id"])
    finally:
        await _borrar(client, creados)
        await _reactivar(client, originales)


async def test_reactivar_falla_si_ya_hay_3_activos(client: AsyncClient) -> None:
    originales = await _aparcar_originales(client)
    creados: list[str] = []
    try:
        # 3 activos
        for i in (1, 2, 3):
            r = await client.post(
                "/api/v1/proyectos", json={"nombre": f"_test_reactivar_{i}"}
            )
            assert r.status_code == 201
            creados.append(r.json()["id"])

        # Uno aparcado aparte
        r = await client.post(
            "/api/v1/proyectos",
            json={"nombre": "_test_reactivar_aparcado", "estado": "aparcado"},
        )
        assert r.status_code == 201
        aparcado_id = r.json()["id"]
        creados.append(aparcado_id)

        # Intentar reactivar: 409
        r = await client.patch(
            f"/api/v1/proyectos/{aparcado_id}", json={"estado": "activo"}
        )
        assert r.status_code == 409, r.text
    finally:
        await _borrar(client, creados)
        await _reactivar(client, originales)


async def test_post_aparcado_no_cuenta_para_tope(client: AsyncClient) -> None:
    originales = await _aparcar_originales(client)
    creados: list[str] = []
    try:
        # 3 activos (ocupan el tope)
        for i in (1, 2, 3):
            r = await client.post(
                "/api/v1/proyectos", json={"nombre": f"_test_topear_{i}"}
            )
            assert r.status_code == 201
            creados.append(r.json()["id"])

        # Un cuarto creado directamente como aparcado: OK, no cuenta
        r = await client.post(
            "/api/v1/proyectos",
            json={"nombre": "_test_topear_extra", "estado": "aparcado"},
        )
        assert r.status_code == 201, r.text
        creados.append(r.json()["id"])
    finally:
        await _borrar(client, creados)
        await _reactivar(client, originales)


# ----------------------------- estados ------------------------------------


async def test_aparcar_y_reactivar_maneja_inactivo_desde(
    client: AsyncClient,
) -> None:
    originales = await _aparcar_originales(client)
    creados: list[str] = []
    try:
        r = await client.post(
            "/api/v1/proyectos", json={"nombre": "_test_inactivo_desde"}
        )
        assert r.status_code == 201
        pid = r.json()["id"]
        creados.append(pid)
        assert r.json()["inactivo_desde"] is None

        # Aparcar fija inactivo_desde
        r = await client.patch(
            f"/api/v1/proyectos/{pid}", json={"estado": "aparcado"}
        )
        assert r.status_code == 200
        assert r.json()["estado"] == "aparcado"
        assert r.json()["inactivo_desde"] is not None

        # Reactivar limpia inactivo_desde
        r = await client.patch(
            f"/api/v1/proyectos/{pid}", json={"estado": "activo"}
        )
        assert r.status_code == 200
        assert r.json()["estado"] == "activo"
        assert r.json()["inactivo_desde"] is None
    finally:
        await _borrar(client, creados)
        await _reactivar(client, originales)


async def test_ultima_actividad_se_refresca_en_patch(client: AsyncClient) -> None:
    r = await client.post(
        "/api/v1/proyectos",
        json={"nombre": "_test_actividad", "estado": "aparcado"},
    )
    assert r.status_code == 201
    pid = r.json()["id"]
    ultima_inicial = r.json()["ultima_actividad_en"]

    try:
        # Pequeña espera para que el timestamp avance de forma medible
        await asyncio.sleep(0.05)
        r = await client.patch(
            f"/api/v1/proyectos/{pid}", json={"descripcion": "cambio"}
        )
        assert r.status_code == 200
        assert r.json()["ultima_actividad_en"] > ultima_inicial
    finally:
        await client.delete(f"/api/v1/proyectos/{pid}")


# ---------------------- coherencia acción siguiente -----------------------


async def test_acc_siguiente_tarea_inexistente_devuelve_422(
    client: AsyncClient,
) -> None:
    r = await client.post(
        "/api/v1/proyectos",
        json={
            "nombre": "_test_acc_inexistente",
            "estado": "aparcado",
            "tarea_siguiente_id": NIL_UUID,
        },
    )
    assert r.status_code == 422, r.text


async def test_acc_siguiente_tarea_libre_se_acepta_y_se_vincula(
    client: AsyncClient, tarea_id: str
) -> None:
    # `tarea_id` viene del fixture en conftest.py — es una tarea recién
    # creada sin proyecto_id. Debe aceptarse como acción siguiente Y
    # quedar asociada (proyecto_id de la tarea apunta al proyecto).
    r = await client.post(
        "/api/v1/proyectos",
        json={
            "nombre": "_test_acc_libre",
            "estado": "aparcado",
            "tarea_siguiente_id": tarea_id,
        },
    )
    assert r.status_code == 201, r.text
    proy_id = r.json()["id"]

    try:
        r = await client.get(f"/api/v1/tareas/{tarea_id}")
        assert r.status_code == 200
        assert r.json()["proyecto_id"] == proy_id, (
            "la tarea libre debió quedar asociada al proyecto al "
            "aceptarse como acción siguiente"
        )
    finally:
        await client.delete(f"/api/v1/proyectos/{proy_id}")


async def test_patch_acc_siguiente_vincula_tarea_libre(
    client: AsyncClient,
) -> None:
    # Creamos un proyecto sin acción siguiente; luego, vía PATCH, le
    # asignamos una tarea libre y verificamos que queda asociada.
    r = await client.post(
        "/api/v1/proyectos",
        json={"nombre": "_test_patch_vincular", "estado": "aparcado"},
    )
    assert r.status_code == 201
    proy_id = r.json()["id"]

    r = await client.post(
        "/api/v1/tareas", json={"titulo": "_test_tarea_a_vincular"}
    )
    assert r.status_code == 201
    tar_id = r.json()["id"]
    assert r.json()["proyecto_id"] is None

    try:
        r = await client.patch(
            f"/api/v1/proyectos/{proy_id}",
            json={"tarea_siguiente_id": tar_id},
        )
        assert r.status_code == 200, r.text

        r = await client.get(f"/api/v1/tareas/{tar_id}")
        assert r.status_code == 200
        assert r.json()["proyecto_id"] == proy_id
    finally:
        await client.delete(f"/api/v1/tareas/{tar_id}/permanente")
        await client.delete(f"/api/v1/proyectos/{proy_id}")


async def test_acc_siguiente_tarea_de_otro_proyecto_devuelve_409(
    client: AsyncClient,
) -> None:
    # Creamos dos proyectos aparcados (para no chocar con tope) y una
    # tarea ligada al primero. Luego intentamos marcarla como acción
    # siguiente del segundo: 409.
    r = await client.post(
        "/api/v1/proyectos",
        json={"nombre": "_test_pA", "estado": "aparcado"},
    )
    assert r.status_code == 201
    proy_a = r.json()["id"]

    r = await client.post(
        "/api/v1/proyectos",
        json={"nombre": "_test_pB", "estado": "aparcado"},
    )
    assert r.status_code == 201
    proy_b = r.json()["id"]

    r = await client.post(
        "/api/v1/tareas",
        json={"titulo": "_test_acc_cruzada", "proyecto_id": proy_a},
    )
    assert r.status_code == 201
    tarea = r.json()["id"]

    try:
        r = await client.patch(
            f"/api/v1/proyectos/{proy_b}",
            json={"tarea_siguiente_id": tarea},
        )
        assert r.status_code == 409, r.text
    finally:
        await client.delete(f"/api/v1/tareas/{tarea}/permanente")
        await client.delete(f"/api/v1/proyectos/{proy_b}")
        await client.delete(f"/api/v1/proyectos/{proy_a}")


# ------------------- número de orden (prioridad) único --------------------


async def test_prioridad_no_se_repite_entre_activos(
    client: AsyncClient,
) -> None:
    """Dos activos no pueden compartir el número de orden. Crear/editar
    con un número ya ocupado por otro activo → 409."""
    originales = await _aparcar_originales(client)
    creados: list[str] = []
    try:
        r1 = await client.post(
            "/api/v1/proyectos",
            json={"nombre": "_test_prio_uno", "prioridad": 1},
        )
        assert r1.status_code == 201, r1.text
        creados.append(r1.json()["id"])

        # Otro activo con el MISMO #1 → 409.
        r2 = await client.post(
            "/api/v1/proyectos",
            json={"nombre": "_test_prio_dos", "prioridad": 1},
        )
        assert r2.status_code == 409, r2.text

        # Con #2 libre → ok.
        r3 = await client.post(
            "/api/v1/proyectos",
            json={"nombre": "_test_prio_tres", "prioridad": 2},
        )
        assert r3.status_code == 201, r3.text
        creados.append(r3.json()["id"])

        # Editar el segundo a #1 (ocupado) → 409.
        r4 = await client.patch(
            f"/api/v1/proyectos/{creados[1]}", json={"prioridad": 1}
        )
        assert r4.status_code == 409, r4.text
    finally:
        await _borrar(client, creados)
        await _reactivar(client, originales)
