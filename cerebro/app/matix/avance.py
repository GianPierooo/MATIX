"""Porcentaje de avance por proyecto, calculado desde el árbol (Paso 2).

El NÚMERO sale del árbol, no lo inventa el modelo: completitud ponderada de
nodos. Maneja la elaboración progresiva (fases lejanas gruesas con pocos nodos,
fase actual fina con muchos) ponderando POR FASE: cada fase aporta su peso al
total y dentro de cada fase su propia completitud. Así contar hojas crudo no
engaña (la fase muy detallada no hunde artificialmente el %).

Todo es PURO (sin BD): se calcula al vuelo y se testea bien.
"""
from __future__ import annotations

from typing import Any

# Una hoja vale según su estado.
_VALOR_ESTADO = {"hecho": 1.0, "en_curso": 0.5, "pendiente": 0.0}
# Peso por tamaño estimado (donde exista); si no, peso parejo (1.0).
_PESO_TAMANO = {"chico": 1.0, "medio": 2.0, "grande": 3.0}


def _peso(nodo: dict[str, Any]) -> float:
    t = (nodo.get("tamano") or "").strip().lower()
    return _PESO_TAMANO.get(t, 1.0)


def _completitud(nodo: dict[str, Any], hijos_de: dict[Any, list[dict]]) -> float:
    """Completitud [0..1] de un nodo. HOJA: por su estado. INTERNO: promedio
    ponderado de sus hijos (su propio estado no cuenta: lo define su contenido).
    """
    hijos = hijos_de.get(nodo.get("id"))
    if not hijos:
        return _VALOR_ESTADO.get(nodo.get("estado"), 0.0)
    total = sum(_peso(h) for h in hijos)
    if total == 0:
        return 0.0
    return sum(_peso(h) * _completitud(h, hijos_de) for h in hijos) / total


def _por_padre(nodos: list[dict[str, Any]]) -> dict[Any, list[dict]]:
    hijos_de: dict[Any, list[dict]] = {}
    for n in nodos:
        hijos_de.setdefault(n.get("parent_id"), []).append(n)
    for lista in hijos_de.values():
        lista.sort(key=lambda x: x.get("orden", 0))
    return hijos_de


def porcentaje(nodos: list[dict[str, Any]]) -> int | None:
    """% de avance del proyecto (0..100), o None si no hay plan/árbol.

    Pondera POR FASE RAÍZ: cada fase contribuye `peso(fase)` al total y aporta
    su completitud. Una fase gruesa pendiente (lejana) cuenta como una unidad a
    0; la fase actual fina aporta su fracción real — sin que su detalle la
    penalice frente a las fases todavía sin desglosar.
    """
    if not nodos:
        return None
    hijos_de = _por_padre(nodos)
    raices = hijos_de.get(None, [])
    if not raices:
        return None
    total = sum(_peso(r) for r in raices)
    if total == 0:
        return None
    avance = sum(_peso(r) * _completitud(r, hijos_de) for r in raices) / total
    return round(avance * 100)


def desglose_por_fase(nodos: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """% por cada fase raíz, en orden. Para que el modelo lea dónde está sólido
    y dónde no (no para mostrar crudo al usuario)."""
    if not nodos:
        return []
    hijos_de = _por_padre(nodos)
    salida: list[dict[str, Any]] = []
    for r in hijos_de.get(None, []):
        salida.append({
            "id": r.get("id"),
            "fase": r.get("titulo", ""),
            "porcentaje": round(_completitud(r, hijos_de) * 100),
            "granularidad": r.get("granularidad"),
            "estado": r.get("estado"),
            "tiene_hijos": bool(hijos_de.get(r.get("id"))),
        })
    return salida
