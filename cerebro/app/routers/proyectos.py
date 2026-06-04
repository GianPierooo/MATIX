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

from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

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
TOPE_ACTIVOS = 3
MSG_TOPE = (
    f"Ya tienes {TOPE_ACTIVOS} proyectos activos: "
    "aparca o termina uno primero."
)


def _ahora_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


async def _contar_activos(db: Postgrest, *, excluir_id: str | None = None) -> int:
    """Cuenta proyectos de TRABAJO activos (es_skill=false). Las skills NO
    consumen el tope de 3: tienen su propio tope blando."""
    activos = await db.list(TABLE, filters={"estado": "activo"})
    activos = [p for p in activos if not p.get("es_skill")]
    if excluir_id:
        activos = [p for p in activos if p["id"] != excluir_id]
    return len(activos)


def _msg_prioridad(n: int) -> str:
    return (
        f"Ya tienes un proyecto activo con el número {n}. "
        "Elige otro o libera ese primero."
    )


async def _prioridad_ocupada(
    db: Postgrest, prioridad: int, *, excluir_id: str | None = None
) -> bool:
    """`True` si OTRO proyecto activo ya usa ese número de orden. El
    `prioridad` es el ranking 1/2/3 entre los activos y no puede
    repetirse — cada activo ocupa una posición distinta."""
    activos = await db.list(TABLE, filters={"estado": "activo"})
    for p in activos:
        if excluir_id and p["id"] == excluir_id:
            continue
        if p.get("prioridad") == prioridad:
            return True
    return False


async def _validar_acc_siguiente(
    db: Postgrest, tarea_id: str, *, proyecto_id: str | None
) -> dict:
    """Valida y devuelve la tarea referenciada como acción siguiente.

    - 422 si la tarea no existe.
    - 409 si la tarea ya está colgada de otro proyecto.
    - Si la tarea está libre (sin `proyecto_id`), se devuelve para que
      el caller la asocie al proyecto con `_vincular_tarea_si_libre`.
    """
    tarea = await db.get("tareas", tarea_id)
    if tarea is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=f"La tarea {tarea_id} no existe",
        )
    proyecto_tarea = tarea.get("proyecto_id")
    if proyecto_tarea is not None and proyecto_tarea != proyecto_id:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "La tarea referenciada ya pertenece a otro proyecto: "
                "muévela primero o elige otra."
            ),
        )
    return tarea


async def _vincular_tarea_si_libre(
    db: Postgrest, tarea: dict, proyecto_id: str
) -> None:
    """Si la tarea no está asociada a ningún proyecto, se le asigna el
    `proyecto_id` recibido. Un proyecto no debería apuntar a una acción
    siguiente que no figure entre sus tareas.
    """
    if tarea.get("proyecto_id") is None:
        await db.update("tareas", tarea["id"], {"proyecto_id": proyecto_id})


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


@router.post(
    "", response_model=ProyectoRead, status_code=status.HTTP_201_CREATED
)
async def crear_proyecto(
    body: ProyectoCreate, db: Postgrest = Depends(get_db)
) -> dict:
    payload = body.model_dump(mode="json", exclude_none=True)

    # Tope de 3 activos (default del schema es "activo"). Solo aplica a
    # proyectos de TRABAJO: una skill no consume slot (tope blando aparte).
    if payload.get("estado", "activo") == "activo" and not payload.get("es_skill"):
        if await _contar_activos(db) >= TOPE_ACTIVOS:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT, detail=MSG_TOPE
            )
        # El número de orden (prioridad) no se repite entre activos.
        prio = payload.get("prioridad")
        if prio is not None and await _prioridad_ocupada(db, prio):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=_msg_prioridad(prio),
            )

    # Coherencia acción siguiente — en creación el proyecto aún no
    # existe, así que solo verificamos que la tarea no esté ya colgada
    # de otro proyecto. Guardamos la tarea para vincularla después,
    # cuando ya tengamos el id del proyecto.
    tsi = payload.get("tarea_siguiente_id")
    tarea_siguiente: dict | None = None
    if tsi:
        tarea_siguiente = await _validar_acc_siguiente(
            db, tsi, proyecto_id=None
        )

    # Fijamos `ultima_actividad_en` con el reloj del cerebro para que
    # las comparaciones posteriores hechas en PATCH (también con el
    # reloj del cerebro) sean monotónicas. Si lo dejamos al `default
    # now()` de Postgres, una diferencia de reloj entre el cerebro y
    # Supabase puede producir saltos hacia atrás.
    payload["ultima_actividad_en"] = _ahora_iso()

    creado = await db.insert(TABLE, payload)

    # Si la acción siguiente era una tarea libre, la asociamos al
    # proyecto recién creado para mantener la invariante "la acción
    # siguiente pertenece al proyecto".
    if tarea_siguiente is not None:
        await _vincular_tarea_si_libre(db, tarea_siguiente, creado["id"])

    return creado


@router.patch("/{proyecto_id}", response_model=ProyectoRead)
async def actualizar_proyecto(
    proyecto_id: UUID,
    body: ProyectoUpdate,
    db: Postgrest = Depends(get_db),
) -> dict:
    actual = await db.get(TABLE, str(proyecto_id))
    if actual is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Proyecto no encontrado",
        )

    payload: dict = body.model_dump(mode="json", exclude_unset=True)

    # Gestión del cambio de estado
    nuevo_estado = payload.get("estado")
    estado_actual = actual["estado"]
    if nuevo_estado is not None and nuevo_estado != estado_actual:
        if nuevo_estado == "activo":
            # Reactivar: validar tope (sin contarse a sí mismo). El tope duro
            # solo aplica a proyectos de trabajo; una skill no consume slot.
            sera_skill = payload.get("es_skill", actual.get("es_skill"))
            if not sera_skill and await _contar_activos(
                db, excluir_id=str(proyecto_id)
            ) >= TOPE_ACTIVOS:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT, detail=MSG_TOPE
                )
            payload["inactivo_desde"] = None
        else:
            # Aparcar o terminar: marcar momento
            payload["inactivo_desde"] = _ahora_iso()

    # El número de orden no se repite entre activos. Calculamos el estado
    # y la prioridad RESULTANTES tras este PATCH y, si el proyecto queda
    # activo con un número ya ocupado por OTRO activo, lo rechazamos.
    estado_resultante = nuevo_estado if nuevo_estado is not None else estado_actual
    prioridad_resultante = (
        payload["prioridad"] if "prioridad" in payload else actual.get("prioridad")
    )
    if estado_resultante == "activo" and prioridad_resultante is not None:
        if await _prioridad_ocupada(
            db, prioridad_resultante, excluir_id=str(proyecto_id)
        ):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=_msg_prioridad(prioridad_resultante),
            )

    # Coherencia acción siguiente
    tarea_siguiente: dict | None = None
    if "tarea_siguiente_id" in payload and payload["tarea_siguiente_id"]:
        tarea_siguiente = await _validar_acc_siguiente(
            db, payload["tarea_siguiente_id"], proyecto_id=str(proyecto_id)
        )

    # Cualquier edición cuenta como actividad
    payload["ultima_actividad_en"] = _ahora_iso()

    row = await db.update(TABLE, str(proyecto_id), payload)
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Proyecto no encontrado",
        )

    # Vincular la acción siguiente al proyecto si estaba libre
    if tarea_siguiente is not None:
        await _vincular_tarea_si_libre(db, tarea_siguiente, str(proyecto_id))

    return row


@router.delete("/{proyecto_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar_proyecto(
    proyecto_id: UUID, db: Postgrest = Depends(get_db)
) -> None:
    ok = await db.delete(TABLE, str(proyecto_id))
    if not ok:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Proyecto no encontrado",
        )
