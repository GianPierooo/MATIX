"""Puente comando → HTTP, compartido por los routers que envuelven comandos.

Un comando devuelve el resultado canónico `{"ok": ..., "tipo": ..., "datos": ...}`.
El router lo traduce a HTTP: éxito → la fila; error → `HTTPException` con el
status que toca. Vive aquí una sola vez para que NINGÚN router copie este mapeo
(Fase 1 lo tenía inline en `routers/tareas.py`; Fase 2 lo consolida)."""
from __future__ import annotations

from typing import Any

from fastapi import HTTPException, status

# Tipo de error del comando → status HTTP.
STATUS = {
    "no_existe": status.HTTP_404_NOT_FOUND,
    "validacion": status.HTTP_400_BAD_REQUEST,
    "prohibida": status.HTTP_403_FORBIDDEN,
    "interno": status.HTTP_500_INTERNAL_SERVER_ERROR,
    "desconocido": status.HTTP_400_BAD_REQUEST,
    # Proyectos: conflictos de regla (tope de 3, prioridad ocupada, acción
    # siguiente colgada de otro proyecto) y referencia inexistente.
    "tope_proyectos": status.HTTP_409_CONFLICT,
    "prioridad_ocupada": status.HTTP_409_CONFLICT,
    "conflicto": status.HTTP_409_CONFLICT,
    "tarea_no_existe": status.HTTP_422_UNPROCESSABLE_CONTENT,
    # Estados no procesables (la petición se entiende pero no aplica a esta
    # entidad/estado): editar/borrar una ocurrencia de un evento de Google;
    # marcar/operar una acción siguiente que no existe o quedó inconsistente.
    "no_soportado": status.HTTP_422_UNPROCESSABLE_CONTENT,
    "sin_accion_siguiente": status.HTTP_422_UNPROCESSABLE_CONTENT,
    "inconsistencia": status.HTTP_422_UNPROCESSABLE_CONTENT,
}


def datos_o_http(res: dict[str, Any]) -> Any:
    """Resultado canónico del comando → `datos` (ok) o `HTTPException` (error)."""
    if res.get("ok"):
        return res["datos"]
    code = STATUS.get(res.get("tipo"), status.HTTP_400_BAD_REQUEST)
    raise HTTPException(status_code=code, detail=res.get("mensaje", "No se pudo."))
