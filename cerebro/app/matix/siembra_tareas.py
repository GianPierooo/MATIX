"""Siembra de tareas inmediatas desde el árbol de un proyecto.

El árbol (perfil/plan) tiene la descomposición; pero hasta ahora nadie creaba
TAREAS reales en el hub ni fijaba la PRÓXIMA ACCIÓN. Acá, de las hojas finas de
CORTO plazo (las accionables YA), surgen unas pocas tareas reales (dosificación:
no se vuelca todo) enlazadas a su nodo, y se fija la próxima acción del proyecto.
Así el hub tiene qué mostrar y el día tiene qué colocar.

La parte PURA (elegir qué nodos sembrar) se testea sin BD.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from ..db import Postgrest

# Cuántas tareas inmediatas sembrar por proyecto (dosificación: las primeras
# accionables, no las 14 del bloque).
MAX_INMEDIATAS = 3


# ── Lógica pura (testeable sin BD) ───────────────────────────────────────────

def nodos_inmediatos(
    nodos: list[dict[str, Any]], maximo: int = MAX_INMEDIATAS
) -> list[dict[str, Any]]:
    """Las primeras hojas FINAS pendientes y SIN tarea ya enlazada, en orden
    (por fase y por orden dentro de la fase). Son las tareas accionables de corto
    plazo. Respeta dosificación: como mucho `maximo`. PURO."""
    hijos: dict[Any, list[dict[str, Any]]] = {}
    for n in nodos:
        hijos.setdefault(n.get("parent_id"), []).append(n)
    for lista in hijos.values():
        lista.sort(key=lambda x: x.get("orden", 0))

    def es_hoja(n: dict) -> bool:
        return not hijos.get(n.get("id"))

    elegidos: list[dict[str, Any]] = []
    for fase in hijos.get(None, []):
        for h in hijos.get(fase.get("id"), []):
            if len(elegidos) >= maximo:
                return elegidos
            if not es_hoja(h):
                continue
            if h.get("estado") == "hecho":
                continue
            if h.get("granularidad") != "fino":
                continue
            if h.get("tarea_id"):
                continue  # ya surgió como tarea: no duplicar
            elegidos.append(h)
        if len(elegidos) >= maximo:
            break
    return elegidos


# ── Impuro: crea las tareas y fija la próxima acción ─────────────────────────

def _fin_de_hoy_utc() -> str:
    from .planificador_diario import LIMA, _fin_de_hoy_utc
    return _fin_de_hoy_utc(datetime.now(timezone.utc).astimezone(LIMA))


async def sembrar_inmediatas(
    db: Postgrest, proyecto: dict[str, Any], *, maximo: int = MAX_INMEDIATAS
) -> dict[str, Any]:
    """Crea las tareas inmediatas de corto plazo (enlazadas a su nodo) y fija la
    próxima acción si el proyecto no tiene una. Idempotente: salta los nodos que
    ya tienen tarea. NO destructivo (solo crea/enlaza). Devuelve un resumen."""
    nodos = await db.list("arbol_nodos", filters={"proyecto_id": proyecto["id"]}, order="orden.asc")
    inmediatos = nodos_inmediatos(nodos, maximo)
    if not inmediatos:
        return {"creadas": 0, "proxima_id": None}

    creadas: list[dict[str, Any]] = []
    for i, nodo in enumerate(inmediatos):
        payload: dict[str, Any] = {
            "titulo": nodo["titulo"],
            "proyecto_id": proyecto["id"],
        }
        # La PRIMERA (la próxima acción) vence hoy, para que el día la pueda
        # colocar; las demás quedan en la lista sin forzar fecha (dosificación).
        if i == 0:
            payload["vence_en"] = _fin_de_hoy_utc()
        tarea = await db.insert("tareas", payload)
        await db.update("arbol_nodos", nodo["id"], {"tarea_id": tarea["id"]})
        creadas.append(tarea)

    proxima_id = None
    if creadas and not proyecto.get("tarea_siguiente_id"):
        proxima_id = creadas[0]["id"]
        await db.update("proyectos", proyecto["id"], {"tarea_siguiente_id": proxima_id})

    return {"creadas": len(creadas), "proxima_id": proxima_id}
