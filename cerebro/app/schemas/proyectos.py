from __future__ import annotations

from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

EstadoProyecto = Literal["activo", "aparcado", "terminado"]


class ProyectoCreate(BaseModel):
    """Crear un proyecto.

    - `estado` por defecto es `"activo"`. Al crear con `activo`, el
      router valida el tope de 3 activos.
    - `prioridad` 1/2/3 entre los activos (el cerebro la gobierna). Se
      permite null para aparcados/terminados.
    - `tarea_siguiente_id`, si se manda, debe existir; su `proyecto_id`
      debe ser null o apuntar al proyecto que se está creando — pero
      como aún no existe, en POST solo verificamos que la tarea exista
      y que no esté ya colgada de otro proyecto.
    """

    nombre: str = Field(min_length=1)
    descripcion: str | None = None
    estado: EstadoProyecto = "activo"
    prioridad: int | None = Field(default=None, ge=1, le=3)
    linea_meta: str | None = None
    tarea_siguiente_id: UUID | None = None
    bloque_protegido: dict[str, Any] | None = None
    color: str | None = None
    # Skill/hábito (inglés, guitarra…): NO consume el tope de 3 activos y se
    # dosifica ligero. Default false = proyecto de trabajo normal.
    es_skill: bool = False


class ProyectoUpdate(BaseModel):
    """Editar un proyecto. Todos opcionales.

    `ultima_actividad_en` y `inactivo_desde` NO se exponen aquí: los
    gestiona el router. `ultima_actividad_en` se refresca en cada PATCH
    (cualquier edición cuenta como actividad). `inactivo_desde` se fija
    al cambiar a aparcado/terminado y se limpia al volver a activo.
    """

    nombre: str | None = Field(default=None, min_length=1)
    descripcion: str | None = None
    estado: EstadoProyecto | None = None
    prioridad: int | None = Field(default=None, ge=1, le=3)
    linea_meta: str | None = None
    tarea_siguiente_id: UUID | None = None
    bloque_protegido: dict[str, Any] | None = None
    color: str | None = None
    es_skill: bool | None = None


class ProyectoRead(BaseModel):
    id: UUID
    nombre: str
    descripcion: str | None = None
    estado: EstadoProyecto
    prioridad: int | None = None
    linea_meta: str | None = None
    tarea_siguiente_id: UUID | None = None
    ultima_actividad_en: datetime
    bloque_protegido: dict[str, Any] | None = None
    color: str | None = None
    es_skill: bool = False
    inactivo_desde: datetime | None = None
    creado_en: datetime
    actualizado_en: datetime
    # % de avance (0..100) calculado desde el árbol del proyecto, o null si no
    # tiene plan todavía. Lo calcula el cerebro al vuelo; la app pinta la barra.
    avance: int | None = None

    model_config = ConfigDict(from_attributes=True)
