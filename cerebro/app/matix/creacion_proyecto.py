"""Creación de proyecto profunda (intake) + enganche con materiales + guard de
capacidad. Reusa la entrevista (Paso 1) y la generación del árbol (Paso 2); acá
viven solo las piezas nuevas y su LÓGICA PURA (testeable sin BD)."""
from __future__ import annotations

from typing import Any

# Alias por skill de biblioteca_material, para detectar material relacionado a
# partir del nombre/objetivo del proyecto. Todo en minúsculas sin acentos.
_ALIAS_SKILL: dict[str, list[str]] = {
    "ingles": ["ingles", "english"],
    "guitarra": ["guitarra", "guitar"],
    "calistenia": ["calistenia", "calisthenics", "barras"],
    "portugues": ["portugues", "portuguese"],
    "trading": ["trading", "trade", "bolsa", "inversion", "inversiones", "cripto"],
}


def detectar_material(texto: str, skills_disponibles: list[str]) -> str | None:
    """¿Hay material en biblioteca_material relacionado con este proyecto? Matchea
    el nombre/objetivo contra los skills disponibles (por nombre o alias).
    Devuelve el skill (tal como viene en `skills_disponibles`) o None. PURO."""
    t = _norm(texto)
    if not t:
        return None
    for skill in skills_disponibles:
        clave = _norm(skill)
        alias = _ALIAS_SKILL.get(clave, [clave])
        if any(a and a in t for a in alias):
            return skill
    return None


def evaluar_capacidad(
    activos: int, *, tope: int = 3, pendientes_abiertos: int = 0
) -> dict[str, Any]:
    """Guard anti-sobrecompromiso. Devuelve si el cupo duro lo permite, si lo
    RECOMIENDA (cupo + carga), y un motivo honesto. PURO — el cálculo fino de
    tiempo viene en el paso de horario; acá basta cupo + carga.

    `pendientes_abiertos`: tareas/subtareas comprometidas sin cerrar, como señal
    de carga real."""
    lleno = activos >= tope
    carga_alta = activos >= 2 and pendientes_abiertos >= 8
    recomienda = (not lleno) and (not carga_alta)
    if lleno:
        motivo = (
            f"Ya tienes {activos} proyectos activos (el tope es {tope}). No te "
            "recomiendo abrir otro sin aparcar o terminar uno: dispersarte baja "
            "la tracción de todos."
        )
    elif carga_alta:
        motivo = (
            f"Tienes {activos} activos y bastante carga abierta "
            f"({pendientes_abiertos} pendientes). Te lo cuestiono: sumar otro "
            "ahora puede ser sobrecompromiso. ¿Seguro, o cerramos algo primero?"
        )
    else:
        libres = tope - activos
        motivo = f"Tienes espacio ({libres} cupo(s) libre(s)); adelante si te cuadra."
    return {
        "permite_duro": not lleno,
        "recomienda": recomienda,
        "espacio": max(0, tope - activos),
        "activos": activos,
        "tope": tope,
        "motivo": motivo,
    }


def intake_suficiente(perfil: dict[str, Any]) -> bool:
    """¿Hay suficiente del intake para PROPONER el árbol? Basta el objetivo y al
    menos componentes o próximos pasos. PURO — dispara la generación del árbol."""
    tiene_objetivo = bool((perfil.get("objetivo") or "").strip()) if isinstance(perfil.get("objetivo"), str) else bool(perfil.get("objetivo"))
    tiene_estructura = bool(perfil.get("componentes")) or bool(perfil.get("proximos_pasos"))
    return tiene_objetivo and tiene_estructura


def _norm(s: Any) -> str:
    r = (s or "")
    r = r.lower().strip() if isinstance(r, str) else ""
    con, sin = "áàäâãéèëêíìïîóòöôõúùüûñ", "aaaaaeeeeiiiiooooouuuun"
    for i in range(len(con)):
        r = r.replace(con[i], sin[i])
    return r
