"""Repetición de tareas al completar: al marcar como completada una
tarea con `repeticion`, el cerebro crea automáticamente la próxima
instancia con `vence_en` desplazado."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from httpx import AsyncClient


async def test_repeticion_diaria_crea_siguiente_al_completar(
    client: AsyncClient,
) -> None:
    vence = datetime.now(timezone.utc) + timedelta(days=1)
    r = await client.post(
        "/api/v1/tareas",
        json={
            "titulo": "_test_rep_diaria",
            "vence_en": vence.isoformat(),
            "repeticion": "diaria",
        },
    )
    assert r.status_code == 201
    original_id = r.json()["id"]

    # Listado inicial: cuántas tareas con ese título existen
    r = await client.get("/api/v1/tareas")
    n_antes = sum(1 for t in r.json() if t["titulo"] == "_test_rep_diaria")

    try:
        # Completar la tarea
        r = await client.patch(
            f"/api/v1/tareas/{original_id}", json={"completada": True}
        )
        assert r.status_code == 200

        # Ahora debe haber UNA tarea más con ese título
        r = await client.get("/api/v1/tareas")
        nuevas = [t for t in r.json() if t["titulo"] == "_test_rep_diaria"]
        assert len(nuevas) == n_antes + 1

        # La nueva (no la original) tiene vence_en ~24h después
        nueva = next(
            t for t in nuevas if t["id"] != original_id and not t["completada"]
        )
        nuevo_vence = datetime.fromisoformat(
            nueva["vence_en"].replace("Z", "+00:00")
        )
        diff = nuevo_vence - vence
        assert timedelta(hours=23) < diff < timedelta(hours=25)

        await client.delete(f"/api/v1/tareas/{nueva['id']}")
    finally:
        await client.delete(f"/api/v1/tareas/{original_id}/permanente")


async def test_completar_sin_repeticion_no_crea_nueva(
    client: AsyncClient,
) -> None:
    r = await client.post(
        "/api/v1/tareas",
        json={
            "titulo": "_test_sin_rep",
            "vence_en": (
                datetime.now(timezone.utc) + timedelta(hours=2)
            ).isoformat(),
        },
    )
    tid = r.json()["id"]
    try:
        r = await client.get("/api/v1/tareas")
        n_antes = sum(1 for t in r.json() if t["titulo"] == "_test_sin_rep")

        r = await client.patch(
            f"/api/v1/tareas/{tid}", json={"completada": True}
        )
        assert r.status_code == 200

        r = await client.get("/api/v1/tareas")
        n_despues = sum(1 for t in r.json() if t["titulo"] == "_test_sin_rep")
        assert n_despues == n_antes  # nada nuevo
    finally:
        await client.delete(f"/api/v1/tareas/{tid}/permanente")
