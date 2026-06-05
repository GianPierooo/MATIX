"""CRUD de `tareas` con borrado suave (Capa 2 Paso 5).

Modelo:

- `GET /tareas`               → solo no eliminadas (vista normal del hub).
- `GET /tareas?papelera=true` → solo eliminadas (vista Papelera).
- `GET /tareas/{id}`          → devuelve la fila aunque esté eliminada
                                (la UI de Papelera necesita verla).
- `POST /tareas`              → crear.
- `PATCH /tareas/{id}`        → editar campos sueltos (incluye
                                `completada`, que dispara la lógica de
                                repetición).
- `DELETE /tareas/{id}`       → borrado SUAVE (set `eliminado_en=now()`).
- `POST /tareas/{id}/restaurar` → quita el `eliminado_en` (vuelve del
                                papelera).
- `DELETE /tareas/{id}/permanente` → DELETE real. Sólo se llama
                                desde la UI cuando el usuario "vacía
                                la papelera". Matix NUNCA debe tener
                                una tool que llegue acá.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status

from ..db import Postgrest, get_db
from ..schemas.tareas import TareaCreate, TareaRead, TareaUpdate
from ..security import require_api_key

router = APIRouter(
    prefix="/tareas",
    tags=["tareas"],
    dependencies=[Depends(require_api_key)],
)

TABLE = "tareas"


def _ahora_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


@router.get("", response_model=list[TareaRead])
async def listar_tareas(
    papelera: bool = Query(default=False),
    db: Postgrest = Depends(get_db),
) -> list[dict]:
    raw_filters = {
        "eliminado_en": "not.is.null" if papelera else "is.null",
    }
    return await db.list(
        TABLE,
        order="creada_en.desc",
        raw_filters=raw_filters,
    )


@router.get("/{tarea_id}", response_model=TareaRead)
async def obtener_tarea(
    tarea_id: UUID, db: Postgrest = Depends(get_db)
) -> dict:
    row = await db.get(TABLE, str(tarea_id))
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Tarea no encontrada"
        )
    return row


@router.post("", response_model=TareaRead, status_code=status.HTTP_201_CREATED)
async def crear_tarea(body: TareaCreate, db: Postgrest = Depends(get_db)) -> dict:
    payload = body.model_dump(mode="json", exclude_none=True)
    return await db.insert(TABLE, payload)


@router.patch("/{tarea_id}", response_model=TareaRead)
async def actualizar_tarea(
    tarea_id: UUID, body: TareaUpdate, db: Postgrest = Depends(get_db)
) -> dict:
    actual = await db.get(TABLE, str(tarea_id))
    if actual is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Tarea no encontrada"
        )

    payload = body.model_dump(mode="json", exclude_unset=True)
    row = await db.update(TABLE, str(tarea_id), payload)
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Tarea no encontrada"
        )

    # Si la tarea se acaba de marcar como completada Y tiene repetición,
    # se crea automáticamente la próxima instancia con `vence_en`
    # desplazado según el patrón (diaria/semanal/mensual/anual).
    se_completa_ahora = (
        payload.get("completada") is True and not actual.get("completada")
    )
    repeticion = actual.get("repeticion") or payload.get("repeticion")
    if se_completa_ahora and repeticion and actual.get("vence_en"):
        await _crear_siguiente_instancia(db, actual, repeticion)

    # Sincroniza con el árbol del proyecto: completar/reabrir una tarea enlazada
    # a un nodo marca ese nodo hecho/pendiente, para que el % de avance suba/baje
    # de verdad. Best-effort: si no es tarea de un plan, no toca nada.
    if "completada" in payload and payload["completada"] != actual.get("completada"):
        try:
            from ..matix import arbol_proyecto

            await arbol_proyecto.marcar_por_tarea(
                db,
                tarea_id=str(tarea_id),
                estado="hecho" if payload["completada"] else "pendiente",
            )
        except Exception:  # noqa: BLE001
            pass

    return row


@router.delete("/{tarea_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar_tarea(
    tarea_id: UUID, db: Postgrest = Depends(get_db)
) -> None:
    """Borrado SUAVE — manda a la papelera.

    Idempotente: si ya estaba en la papelera, no error.
    """
    row = await db.update(
        TABLE, str(tarea_id), {"eliminado_en": _ahora_iso()}
    )
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Tarea no encontrada"
        )


@router.post("/{tarea_id}/restaurar", response_model=TareaRead)
async def restaurar_tarea(
    tarea_id: UUID, db: Postgrest = Depends(get_db)
) -> dict:
    row = await db.update(TABLE, str(tarea_id), {"eliminado_en": None})
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Tarea no encontrada"
        )
    return row


@router.delete(
    "/{tarea_id}/permanente", status_code=status.HTTP_204_NO_CONTENT
)
async def eliminar_tarea_permanente(
    tarea_id: UUID, db: Postgrest = Depends(get_db)
) -> None:
    """Borrado DURO — destruye la fila. Solo desde la UI al vaciar
    la papelera. Matix no tiene una tool que llegue acá."""
    ok = await db.delete(TABLE, str(tarea_id))
    if not ok:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Tarea no encontrada"
        )


# ---------------------------------------------------------------------------


def _avanzar_fecha(iso: str, repeticion: str) -> str:
    """Avanza un timestamp ISO 8601 según `repeticion`."""
    dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    if repeticion == "diaria":
        nuevo = dt + timedelta(days=1)
    elif repeticion == "semanal":
        nuevo = dt + timedelta(weeks=1)
    elif repeticion == "mensual":
        # 30 días simple — el mes "real" se puede afinar con dateutil
        # si la imprecisión molesta.
        nuevo = dt + timedelta(days=30)
    elif repeticion == "anual":
        nuevo = dt + timedelta(days=365)
    else:
        nuevo = dt
    return nuevo.isoformat()


async def _crear_siguiente_instancia(
    db: Postgrest, original: dict, repeticion: str
) -> None:
    """Crea una nueva tarea idéntica con `vence_en` desplazado.

    Si el original tenía `recordar_en`, se desplaza el mismo delta
    para mantener la antelación relativa.
    """
    nueva: dict = {
        "titulo": original["titulo"],
        "prioridad": original["prioridad"],
        "repeticion": repeticion,
        "vence_en": _avanzar_fecha(original["vence_en"], repeticion),
    }
    for campo in ("nota", "categoria_id", "curso_id", "proyecto_id"):
        if original.get(campo) is not None:
            nueva[campo] = original[campo]

    if original.get("recordar_en"):
        nueva["recordar_en"] = _avanzar_fecha(
            original["recordar_en"], repeticion
        )

    await db.insert(TABLE, nueva)
