"""Router CRUD de `proyectos` con las reglas del Documento Maestro:

- **Tope de 3 activos**: crear o reactivar un proyecto que dejaría más
  de 3 con estado `activo` devuelve 409. La regla vive aquí (no en la
  BD) para que el mensaje al usuario sea legible.
- **Coherencia acción siguiente ↔ proyecto**: si una tarea es marcada
  como `tarea_siguiente_id` de un proyecto, su `proyecto_id` debe ser
  NULL o apuntar a ese mismo proyecto.
- **`inactivo_desde`** se gestiona aquí: se fija al pasar a aparcado /
  terminado, se limpia al volver a activo.
- **`ultima_actividad_en`** se refresca en cada PATCH (cualquier
  edición del proyecto cuenta como actividad).
"""
from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from ..comandos import registro
from ..comandos.http import datos_o_http as _datos_o_http
from ..db import Postgrest, get_db
from ..matix import avance as avance_mod
from ..schemas.proyectos import ProyectoCreate, ProyectoRead, ProyectoUpdate
from ..security import require_api_key

router = APIRouter(
    prefix="/proyectos",
    tags=["proyectos"],
    dependencies=[Depends(require_api_key)],
)

TABLE = "proyectos"


async def _avance_por_proyecto(
    db: Postgrest, proyecto_ids: list[str]
) -> dict[str, int | None]:
    """% de avance de cada proyecto (calculado al vuelo desde su árbol). Un
    solo query para todos los nodos de los proyectos dados; agrupa y pondera.
    Best-effort: si falla, devuelve {} y la barra simplemente no aparece."""
    if not proyecto_ids:
        return {}
    try:
        ids_csv = ",".join(proyecto_ids)
        nodos = await db.list(
            "arbol_nodos",
            raw_filters={"proyecto_id": f"in.({ids_csv})"},
            limit=5000,
        )
    except Exception:  # noqa: BLE001
        return {}
    por_proyecto: dict[str, list[dict]] = {}
    for n in nodos:
        por_proyecto.setdefault(str(n.get("proyecto_id")), []).append(n)
    return {pid: avance_mod.porcentaje(por_proyecto.get(pid, [])) for pid in proyecto_ids}


@router.get("", response_model=list[ProyectoRead])
async def listar_proyectos(db: Postgrest = Depends(get_db)) -> list[dict]:
    # Activos primero por prioridad (1, 2, 3), luego creación reciente.
    filas = await db.list(TABLE, order="prioridad.asc.nullslast,creado_en.desc")
    avances = await _avance_por_proyecto(db, [str(f["id"]) for f in filas])
    for f in filas:
        f["avance"] = avances.get(str(f["id"]))
    return filas


@router.get("/{proyecto_id}", response_model=ProyectoRead)
async def obtener_proyecto(
    proyecto_id: UUID, db: Postgrest = Depends(get_db)
) -> dict:
    row = await db.get(TABLE, str(proyecto_id))
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Proyecto no encontrado",
        )
    avances = await _avance_por_proyecto(db, [str(row["id"])])
    row["avance"] = avances.get(str(row["id"]))
    return row


@router.get("/{proyecto_id}/arbol")
async def obtener_arbol(
    proyecto_id: UUID, db: Postgrest = Depends(get_db)
) -> dict:
    """Descomposición (árbol) del proyecto para mostrarla en el detalle: fases
    (corto fino / medio-largo grueso) → pasos. Devuelve los nodos planos (la app
    arma el árbol por `parent_id`) + el % de avance calculado del árbol."""
    row = await db.get(TABLE, str(proyecto_id))
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Proyecto no encontrado"
        )
    nodos = await db.list(
        "arbol_nodos", filters={"proyecto_id": str(proyecto_id)}, order="orden.asc"
    )
    return {"nodos": nodos, "avance": avance_mod.porcentaje(nodos)}


@router.post(
    "", response_model=ProyectoRead, status_code=status.HTTP_201_CREATED
)
async def crear_proyecto(
    body: ProyectoCreate, db: Postgrest = Depends(get_db)
) -> dict:
    """Crea por el comando `crear_proyecto` (misma ruta que la IA): tope de 3,
    prioridad única, coherencia de la acción siguiente, `ultima_actividad_en`."""
    res = await registro.ejecutar(
        db, "crear_proyecto", body.model_dump(mode="json", exclude_none=True), origen="ui"
    )
    return _datos_o_http(res)


@router.patch("/{proyecto_id}", response_model=ProyectoRead)
async def actualizar_proyecto(
    proyecto_id: UUID,
    body: ProyectoUpdate,
    db: Postgrest = Depends(get_db),
) -> dict:
    """Edita por el comando `editar_proyecto` (incluye cambio de estado con su
    tope, `inactivo_desde`, prioridad única y coherencia de la acción siguiente)."""
    params = {**body.model_dump(mode="json", exclude_unset=True), "proyecto_id": str(proyecto_id)}
    res = await registro.ejecutar(db, "editar_proyecto", params, origen="ui")
    return _datos_o_http(res)


@router.delete("/{proyecto_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar_proyecto(
    proyecto_id: UUID, db: Postgrest = Depends(get_db)
) -> None:
    res = await registro.ejecutar(
        db, "eliminar_proyecto", {"proyecto_id": str(proyecto_id)}, origen="ui"
    )
    _datos_o_http(res)
