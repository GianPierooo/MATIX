"""Árbol de descomposición vivo por proyecto (perfil profundo · Paso 2).

Sustrato de planificación: un árbol de nodos (fases → pasos) por proyecto
activo, generado desde su PERFIL (0029). De acá saldrán, en el Paso 3, las
subtareas diarias — pero ESTE paso solo construye y mantiene el árbol.

SEPARADO de la lista de Tareas del hub: los nodos NO se vuelcan a `tareas`.

Elaboración progresiva (anti-abrumo): la fase ACTUAL se detalla fino; las
lejanas quedan gruesas (`granularidad='grueso'`) y se refinan al acercarse.

La parte PURA (armado de la propuesta, render, progreso, sync con tareas
completadas) está al final y se testea sin BD.
"""
from __future__ import annotations

from typing import Any

from ..db import Postgrest
from . import perfil_proyecto


# ── Generación / lectura ────────────────────────────────────────────────────

async def generar_arbol(db: Postgrest, *, proyecto: dict[str, Any]) -> dict[str, Any]:
    """Arma un árbol inicial desde el perfil y lo guarda PARA REVISIÓN. Si ya
    hay árbol, no lo duplica: devuelve el existente para editar/refinar."""
    existentes = await db.list("arbol_nodos", filters={"proyecto_id": proyecto["id"]}, limit=1)
    if existentes:
        return {"estado": "ya_existe", "nodos": await _nodos(db, proyecto["id"])}

    perfil = await perfil_proyecto.ver_perfil(db, proyecto)
    propuesta = armar_propuesta_arbol(perfil)
    if not propuesta:
        return {"estado": "sin_perfil"}

    await _insertar_propuesta(db, proyecto["id"], propuesta)
    return {"estado": "generado", "nodos": await _nodos(db, proyecto["id"])}


async def ver_arbol(db: Postgrest, *, proyecto: dict[str, Any]) -> list[dict[str, Any]]:
    return await _nodos(db, proyecto["id"])


async def _nodos(db: Postgrest, proyecto_id: str) -> list[dict[str, Any]]:
    return await db.list(
        "arbol_nodos", filters={"proyecto_id": proyecto_id}, order="orden.asc"
    )


async def _insertar_propuesta(
    db: Postgrest, proyecto_id: str, propuesta: list[dict[str, Any]]
) -> None:
    """Inserta el árbol propuesto: primero las raíces, luego sus hijos con el
    parent_id ya resuelto."""
    for i, raiz in enumerate(propuesta):
        fila = await db.insert(
            "arbol_nodos",
            {
                "proyecto_id": proyecto_id,
                "parent_id": None,
                "titulo": raiz["titulo"],
                "orden": i,
                "fase": raiz.get("fase"),
                "granularidad": raiz.get("granularidad", "grueso"),
            },
        )
        for j, hijo in enumerate(raiz.get("hijos", [])):
            await db.insert(
                "arbol_nodos",
                {
                    "proyecto_id": proyecto_id,
                    "parent_id": fila["id"],
                    "titulo": hijo["titulo"],
                    "orden": j,
                    "fase": raiz.get("fase"),
                    "granularidad": "fino",
                },
            )


# ── Edición de nodos ────────────────────────────────────────────────────────

async def agregar_nodo(
    db: Postgrest, *, proyecto_id: str, titulo: str, parent_id: str | None = None,
    fase: str | None = None, tamano: str | None = None, notas: str | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {"proyecto_id": proyecto_id, "titulo": titulo}
    if parent_id:
        payload["parent_id"] = parent_id
    if fase:
        payload["fase"] = fase
    if tamano:
        payload["tamano"] = tamano
    if notas:
        payload["notas"] = notas
    return await db.insert("arbol_nodos", payload)


async def actualizar_nodo(
    db: Postgrest, *, nodo_id: str, campos: dict[str, Any]
) -> dict[str, Any] | None:
    permitidos = {"titulo", "estado", "orden", "notas", "tamano", "fase", "granularidad"}
    payload = {k: v for k, v in campos.items() if k in permitidos and v is not None}
    if not payload:
        return await db.get("arbol_nodos", nodo_id)
    return await db.update("arbol_nodos", nodo_id, payload)


async def eliminar_nodo(db: Postgrest, *, nodo_id: str) -> bool:
    # Los hijos caen por FK ON DELETE CASCADE.
    return await db.delete("arbol_nodos", nodo_id)


async def refinar_fase(
    db: Postgrest, *, nodo_id: str, subnodos: list[str]
) -> dict[str, Any] | None:
    """Desglosa una fase gruesa en sus pasos finos y la marca 'fino'."""
    padre = await db.get("arbol_nodos", nodo_id)
    if padre is None:
        return None
    for j, titulo in enumerate(subnodos):
        t = (titulo or "").strip()
        if not t:
            continue
        await db.insert(
            "arbol_nodos",
            {
                "proyecto_id": padre["proyecto_id"],
                "parent_id": nodo_id,
                "titulo": t,
                "orden": j,
                "fase": padre.get("fase"),
                "granularidad": "fino",
            },
        )
    return await db.update("arbol_nodos", nodo_id, {"granularidad": "fino"})


# ── Vivo: sync con tareas del hub ───────────────────────────────────────────

async def marcar_por_tarea(db: Postgrest, *, tarea_id: str, estado: str) -> int:
    """Pone `estado` a los nodos enlazados a esa tarea (el Paso 3 crea el
    enlace). Best-effort; devuelve cuántos nodos tocó. En el Paso 2 no hay
    enlaces, así que normalmente es 0 — el hook ya queda vivo."""
    nodos = await db.list("arbol_nodos", filters={"tarea_id": tarea_id})
    for n in nodos:
        await db.update("arbol_nodos", n["id"], {"estado": estado})
    return len(nodos)


# ════════════════════════════════════════════════════════════════════════════
# LÓGICA PURA (testeable sin BD)
# ════════════════════════════════════════════════════════════════════════════

def armar_propuesta_arbol(perfil: dict[str, Any]) -> list[dict[str, Any]]:
    """Construye la propuesta de árbol desde el perfil. Las raíces son los
    COMPONENTES (fases). La fase ACTUAL se detalla FINO con los próximos pasos;
    las demás quedan GRUESAS (placeholder, para refinar al acercarse).

    Devuelve `[{titulo, fase, granularidad, hijos:[{titulo}]}]`.
    """
    componentes = [c.get("contenido", "").strip() for c in perfil.get("componentes", [])]
    componentes = [c for c in componentes if c]
    proximos = [p.get("contenido", "").strip() for p in perfil.get("proximos_pasos", [])]
    proximos = [p for p in proximos if p]
    fase_actual = perfil.get("fase_actual") or ""

    if not componentes:
        # Sin componentes: una sola raíz (objetivo) con los próximos pasos finos.
        raiz_titulo = (perfil.get("objetivo") or perfil.get("nombre") or "Plan").strip()
        return [{
            "titulo": raiz_titulo,
            "fase": fase_actual or None,
            "granularidad": "fino" if proximos else "grueso",
            "hijos": [{"titulo": p} for p in proximos],
        }]

    idx_actual = _indice_fase_actual(componentes, fase_actual)
    arbol: list[dict[str, Any]] = []
    for i, comp in enumerate(componentes):
        es_actual = i == idx_actual
        arbol.append({
            "titulo": comp,
            "fase": comp,
            "granularidad": "fino" if es_actual else "grueso",
            # Solo la fase actual recibe el detalle fino (anti-abrumo).
            "hijos": [{"titulo": p} for p in proximos] if es_actual else [],
        })
    return arbol


def armar_arbol_texto(nodos: list[dict[str, Any]]) -> str:
    """Render del árbol (indentado, con estado e id) para «muéstrame el plan».
    `nodos` son las filas planas (con parent_id)."""
    if not nodos:
        return "Todavía no hay plan para este proyecto. Puedo generarlo desde su perfil."
    hijos_de: dict[Any, list[dict[str, Any]]] = {}
    for n in nodos:
        hijos_de.setdefault(n.get("parent_id"), []).append(n)
    for lista in hijos_de.values():
        lista.sort(key=lambda x: x.get("orden", 0))

    out: list[str] = []

    def _pinta(parent: Any, nivel: int) -> None:
        for n in hijos_de.get(parent, []):
            marca = _marca_estado(n.get("estado"))
            grueso = "  (por desglosar)" if n.get("granularidad") == "grueso" else ""
            tam = f"  [{n['tamano']}]" if n.get("tamano") else ""
            out.append(f"{'  ' * nivel}- {marca}{n.get('titulo', '')}{tam}{grueso}  id={n.get('id')}")
            _pinta(n.get("id"), nivel + 1)

    _pinta(None, 0)
    return "\n".join(out)


def progreso_arbol(nodos: list[dict[str, Any]]) -> dict[str, int]:
    total = len(nodos)
    hechos = sum(1 for n in nodos if n.get("estado") == "hecho")
    en_curso = sum(1 for n in nodos if n.get("estado") == "en_curso")
    return {"total": total, "hechos": hechos, "en_curso": en_curso, "pendientes": total - hechos - en_curso}


def nodos_de_tarea(nodos: list[dict[str, Any]], tarea_id: str) -> list[str]:
    """Ids de los nodos enlazados a una tarea (para el sync al completarla)."""
    return [n["id"] for n in nodos if n.get("tarea_id") == tarea_id]


def _indice_fase_actual(componentes: list[str], fase_actual: str) -> int:
    """Índice del componente que corresponde a la fase actual; si ninguno
    calza, la primera (índice 0) se trata como la actual."""
    f = _norm(fase_actual)
    if f:
        for i, c in enumerate(componentes):
            nc = _norm(c)
            if nc and (f in nc or nc in f):
                return i
    return 0


def _marca_estado(estado: Any) -> str:
    return {"hecho": "[hecho] ", "en_curso": "[en curso] "}.get(estado, "")


def _norm(s: str) -> str:
    r = (s or "").lower().strip()
    con, sin = "áàäâãéèëêíìïîóòöôõúùüûñ", "aaaaaeeeeiiiiooooouuuun"
    for i in range(len(con)):
        r = r.replace(con[i], sin[i])
    return r
