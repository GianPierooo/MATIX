"""CRUD de `tareas` con borrado suave (Capa 2 Paso 5).

2.0 · Fase 1: este router es un ENVOLTORIO DELGADO sobre los COMANDOS de
`app/comandos/tareas.py`. La lógica (incluida repetición + sync árbol/set al
completar) vive UNA sola vez ahí; la tool de la IA llama al MISMO comando, así
que UI e IA hacen exactamente lo mismo por una sola ruta canónica.

Modelo:

- `GET /tareas`               → solo no eliminadas (vista normal del hub).
- `GET /tareas?papelera=true` → solo eliminadas (vista Papelera).
- `GET /tareas/{id}`          → devuelve la fila aunque esté eliminada.
- `POST /tareas`              → comando `crear_tarea`.
- `PATCH /tareas/{id}`        → comando `editar_tarea` (incluye `completada`,
                                que dispara repetición + sync).
- `DELETE /tareas/{id}`       → comando `eliminar_tarea` (borrado SUAVE).
- `POST /tareas/{id}/restaurar` → comando `restaurar_tarea`.
- `DELETE /tareas/{id}/permanente` → DELETE real. Solo desde la UI al vaciar la
                                papelera; NO es un comando (la IA no llega acá).
"""
from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status

from ..comandos import registro
from ..db import Postgrest, get_db
from ..schemas.tareas import TareaCreate, TareaRead, TareaUpdate
from ..security import require_api_key

router = APIRouter(
    prefix="/tareas",
    tags=["tareas"],
    dependencies=[Depends(require_api_key)],
)

TABLE = "tareas"

# Mapa tipo-de-error del comando → status HTTP del endpoint.
_STATUS = {
    "no_existe": status.HTTP_404_NOT_FOUND,
    "validacion": status.HTTP_400_BAD_REQUEST,
    "prohibida": status.HTTP_403_FORBIDDEN,
    "interno": status.HTTP_500_INTERNAL_SERVER_ERROR,
    "desconocido": status.HTTP_400_BAD_REQUEST,
}


def _datos_o_http(res: dict) -> dict:
    """Resultado canónico del comando → fila (ok) o HTTPException (error)."""
    if res.get("ok"):
        return res["datos"]
    code = _STATUS.get(res.get("tipo"), status.HTTP_400_BAD_REQUEST)
    raise HTTPException(status_code=code, detail=res.get("mensaje", "No se pudo."))


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
    res = await registro.ejecutar(
        db, "crear_tarea",
        body.model_dump(mode="json", exclude_none=True),
        origen="ui",
    )
    return _datos_o_http(res)


@router.patch("/{tarea_id}", response_model=TareaRead)
async def actualizar_tarea(
    tarea_id: UUID, body: TareaUpdate, db: Postgrest = Depends(get_db)
) -> dict:
    # Solo los campos que el cliente envió (exclude_unset) + el id. El comando
    # `editar_tarea` aplica el toggle de completada con repetición + sync.
    params = {**body.model_dump(mode="json", exclude_unset=True), "tarea_id": str(tarea_id)}
    res = await registro.ejecutar(db, "editar_tarea", params, origen="ui")
    return _datos_o_http(res)


@router.delete("/{tarea_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar_tarea(
    tarea_id: UUID, db: Postgrest = Depends(get_db)
) -> None:
    """Borrado SUAVE — manda a la papelera (comando `eliminar_tarea`)."""
    res = await registro.ejecutar(
        db, "eliminar_tarea", {"tarea_id": str(tarea_id)}, origen="ui"
    )
    _datos_o_http(res)  # levanta 404 si no existe; ignora el body en 204


@router.post("/{tarea_id}/restaurar", response_model=TareaRead)
async def restaurar_tarea(
    tarea_id: UUID, db: Postgrest = Depends(get_db)
) -> dict:
    res = await registro.ejecutar(
        db, "restaurar_tarea", {"tarea_id": str(tarea_id)}, origen="ui"
    )
    return _datos_o_http(res)


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

# La lógica de repetición (avanzar fecha + crear siguiente instancia) ya NO vive
# aquí: es del comando `editar_tarea`/`completar_tarea` (app/comandos/tareas.py).
