"""Crear un proyecto desde un PLAN YA ARMADO (pegado), sin la entrevista.

El MODELO fuerte parsea el plan en texto a una estructura
(`{objetivo, tipo, parametros, fases:[{titulo, horizonte, nodos}]}`); este
módulo VALIDA, normaliza, detecta huecos y la convierte a perfil + árbol,
respetando la separación árbol vs Tareas (no inunda Tareas) y la elaboración
progresiva (fases lejanas quedan GRUESAS; su detalle se guarda para refinar al
acercarse, no se aplana). Reusa el esquema del intake (parámetros requeridos) y
el árbol (Paso 2).

La parte PURA (normalización, etiquetado de horizonte → granularidad, huecos,
plan → nodos) se testea sin BD. Lo impuro crea el proyecto y los nodos.
"""
from __future__ import annotations

from typing import Any

from ..db import Postgrest
from . import intake_analitico


# Horizonte → granularidad del nodo: solo lo de CORTO plazo se detalla fino
# (elaboración progresiva); medio/largo quedan gruesos (placeholder a refinar).
def granularidad_de_horizonte(horizonte: str) -> str:
    h = (horizonte or "").strip().lower()
    return "fino" if h in ("corto", "corto_plazo", "actual", "ahora") else "grueso"


def normalizar_plan(estructura: dict[str, Any]) -> dict[str, Any]:
    """Normaliza la estructura parseada por el modelo: limpia, infiere tipo si
    falta, etiqueta cada fase con su granularidad y descarta basura. PURO."""
    objetivo = str(estructura.get("objetivo") or "").strip()
    parametros = {
        str(k): str(v).strip()
        for k, v in (estructura.get("parametros") or {}).items()
        if isinstance(v, (str, int, float)) and str(v).strip()
    }
    tipo = str(estructura.get("tipo") or "").strip()
    if tipo not in intake_analitico.TIPOS:
        base = f"{objetivo} {parametros.get('que_vende','')} {parametros.get('meta_plazo','')}"
        tipo = intake_analitico.detectar_tipo(base)

    fases_norm: list[dict[str, Any]] = []
    for i, f in enumerate(estructura.get("fases") or []):
        if not isinstance(f, dict):
            continue
        titulo = str(f.get("titulo") or "").strip()
        if not titulo:
            continue
        horizonte = str(f.get("horizonte") or ("corto" if i == 0 else "largo")).strip().lower()
        nodos = [str(n).strip() for n in (f.get("nodos") or []) if str(n).strip()]
        fases_norm.append({
            "titulo": titulo,
            "horizonte": horizonte,
            "granularidad": granularidad_de_horizonte(horizonte),
            "nodos": nodos,
            "orden": i,
        })
    return {"objetivo": objetivo, "tipo": tipo, "parametros": parametros, "fases": fases_norm}


def huecos_plan(plan: dict[str, Any]) -> dict[str, Any]:
    """Qué parámetros REQUERIDOS le faltan al plan (igual que el intake), para
    pedirlos en vez de inventar. PURO."""
    capturados = dict(plan.get("parametros") or {})
    if plan.get("objetivo"):
        capturados.setdefault("objetivo", plan["objetivo"])
    return intake_analitico.puede_planear(plan.get("tipo", "generico"), capturados)


def decidir_importacion(gate: dict[str, Any], forzar: bool = False) -> str:
    """Crear DIRECTO si el plan está completo (gate listo) o si el usuario fuerza;
    si faltan requeridos, PREGUNTAR antes (no inventar). PURO."""
    return "crear" if (gate.get("listo") or forzar) else "preguntar"


def plan_a_nodos(fases: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Convierte las fases normalizadas a la forma de inserción del árbol:
    - fase CORTO (fina): nodo raíz fino + sus nodos como hijos finos.
    - fase MEDIO/LARGO (gruesa): nodo raíz grueso SIN hijos (elaboración
      progresiva); su detalle se guarda en `notas` para refinar al llegar.
    PURO."""
    out: list[dict[str, Any]] = []
    for f in fases:
        if f["granularidad"] == "fino":
            out.append({
                "titulo": f["titulo"], "granularidad": "fino", "orden": f["orden"],
                "fase": f["titulo"], "notas": None,
                "hijos": [{"titulo": n} for n in f["nodos"]],
            })
        else:
            notas = ("Por desglosar: " + "; ".join(f["nodos"])) if f["nodos"] else None
            out.append({
                "titulo": f["titulo"], "granularidad": "grueso", "orden": f["orden"],
                "fase": f["titulo"], "notas": notas, "hijos": [],
            })
    return out


def resumen_importacion(plan: dict[str, Any]) -> str:
    """Texto del PREVIEW para que el modelo muestre cómo quedó interpretado el
    plan antes de crear (gate de revisión). PURO."""
    L = [f"Así interpreté el plan (tipo: {plan.get('tipo','generico')}):"]
    if plan.get("objetivo"):
        L.append(f"- Objetivo: {plan['objetivo']}")
    for k in ("porque", "meta_plazo", "criterio_exito"):
        v = (plan.get("parametros") or {}).get(k)
        if v:
            etq = {"porque": "Porqué", "meta_plazo": "Meta", "criterio_exito": "Criterio de éxito"}[k]
            L.append(f"- {etq}: {v}")
    L.append("- Plan (árbol):")
    for f in plan.get("fases", []):
        marca = "fina" if f["granularidad"] == "fino" else "gruesa (por desglosar)"
        L.append(f"  · {f['titulo']} [{f['horizonte']} · {marca}]")
        for n in (f["nodos"] if f["granularidad"] == "fino" else []):
            L.append(f"      - {n}")
    return "\n".join(L)


# ════════════════════════════════════════════════════════════════════════════
# Aplicación (impuro): crea el proyecto + el árbol
# ════════════════════════════════════════════════════════════════════════════

_TOPE_ACTIVOS = 3


async def aplicar_importacion(
    db: Postgrest, *, plan: dict[str, Any], nombre: str, proyecto: dict | None = None
) -> dict[str, Any]:
    """Crea (o usa) el proyecto, fija perfil/parámetros y arma el árbol desde el
    plan. Respeta el tope de 3 activos (si está lleno, lo crea aparcado)."""
    if proyecto is None:
        activos = await db.list("proyectos", filters={"estado": "activo"})
        estado = "activo" if len(activos) < _TOPE_ACTIVOS else "aparcado"
        proyecto = await db.insert("proyectos", {
            "nombre": nombre,
            "estado": estado,
            "objetivo": plan.get("objetivo") or None,
            "tipo": plan.get("tipo"),
            "parametros": plan.get("parametros") or {},
        })
    else:
        await db.update("proyectos", proyecto["id"], {
            "objetivo": plan.get("objetivo") or proyecto.get("objetivo"),
            "tipo": plan.get("tipo"),
            "parametros": {**(proyecto.get("parametros") or {}), **(plan.get("parametros") or {})},
        })

    pid = proyecto["id"]
    creados = 0
    for raiz in plan_a_nodos(plan["fases"]):
        payload = {
            "proyecto_id": pid, "parent_id": None, "titulo": raiz["titulo"],
            "orden": raiz["orden"], "fase": raiz["fase"], "granularidad": raiz["granularidad"],
        }
        if raiz.get("notas"):
            payload["notas"] = raiz["notas"]
        fila = await db.insert("arbol_nodos", payload)
        creados += 1
        for j, hijo in enumerate(raiz["hijos"]):
            await db.insert("arbol_nodos", {
                "proyecto_id": pid, "parent_id": fila["id"], "titulo": hijo["titulo"],
                "orden": j, "fase": raiz["fase"], "granularidad": "fino",
            })
            creados += 1
    return {"proyecto": proyecto, "estado": proyecto.get("estado"), "nodos_creados": creados}
