"""Arma el cierre del día (Capa 8 · Paso 2).

Hermano nocturno del briefing matutino. Mientras el briefing prepara
("esto viene hoy"), el cierre cierra: qué pasó, qué quedó, y algo
para soltar antes de dormir.

Tono deliberado — **de cierre, no de exigencia**. No es una lista de
deberes pendientes que generan culpa; es un repaso amable. Lo que
quedó sin hacer se enmarca como "mañana sigues", no como "te falta".

Reusa los helpers de zona horaria y formato de `armar.py` (mismo
paquete) para no duplicar la lógica de Lima/UTC.

Contenido:
- `hechas`: tareas completadas hoy (lo logrado).
- `pendientes_hoy`: tareas que vencían hoy y no se completaron
  (lo que queda, sin dramatismo).
- `manana`: eventos + tareas que vencen mañana (qué viene).
- `cierre_frase`: línea para soltar, adaptada al volumen del día.
"""
from __future__ import annotations

from datetime import timedelta
from typing import Any

from ..db import Postgrest
from .armar import (
    _a_lima,
    _ahora_lima,
    _dia_semana_es,
    _fecha_es,
    _hh_mm,
)


def _contexto_tarea(
    t: dict[str, Any],
    nombre_proyecto: dict[str, str],
    nombre_curso: dict[str, str],
) -> str | None:
    if t.get("proyecto_id"):
        return nombre_proyecto.get(t["proyecto_id"])
    if t.get("curso_id"):
        return nombre_curso.get(t["curso_id"])
    return None


async def armar_cierre(db: Postgrest) -> dict[str, Any]:
    """Arma el cierre del día actual. Devuelve un dict serializable
    con `resumen_corto` (body de la notificación) y `texto_para_voz`
    (para el botón TTS)."""
    ahora = _ahora_lima()
    hoy = ahora.date()
    manana = hoy + timedelta(days=1)

    tareas = await db.list(
        "tareas", raw_filters={"eliminado_en": "is.null"}
    )
    cursos = await db.list("cursos")
    nombre_curso = {c["id"]: c["nombre"] for c in cursos}
    proyectos = await db.list("proyectos")
    nombre_proyecto = {p["id"]: p["nombre"] for p in proyectos}

    hechas: list[dict[str, Any]] = []
    pendientes_hoy: list[dict[str, Any]] = []
    tareas_manana: list[dict[str, Any]] = []

    for t in tareas:
        contexto = _contexto_tarea(t, nombre_proyecto, nombre_curso)
        if t.get("completada"):
            # Solo las completadas HOY (en Lima) cuentan como "lo de hoy".
            ce = _a_lima(t.get("completada_en"))
            if ce and ce.date() == hoy:
                hechas.append({"titulo": t["titulo"], "contexto": contexto})
            continue
        v = _a_lima(t.get("vence_en"))
        if not v:
            continue
        item = {
            "titulo": t["titulo"],
            "prioridad": t.get("prioridad") or "media",
            "contexto": contexto,
        }
        if v.date() == hoy:
            pendientes_hoy.append(item)
        elif v.date() == manana:
            tareas_manana.append(item)

    _prio = {"alta": 0, "media": 1, "baja": 2}
    pendientes_hoy.sort(key=lambda t: _prio.get(t["prioridad"], 9))
    tareas_manana.sort(key=lambda t: _prio.get(t["prioridad"], 9))

    # Eventos de mañana.
    eventos_raw = await db.list(
        "eventos", raw_filters={"eliminado_en": "is.null"}
    )
    eventos_manana: list[dict[str, Any]] = []
    for e in eventos_raw:
        ini = _a_lima(e.get("inicia_en"))
        if ini and ini.date() == manana:
            eventos_manana.append(e)
    eventos_manana.sort(key=lambda e: e["inicia_en"])
    eventos_manana_fmt = [
        {
            "hora": _hh_mm(e.get("inicia_en")),
            "titulo": e["titulo"],
            "todo_el_dia": bool(e.get("todo_el_dia")),
        }
        for e in eventos_manana
    ]

    cierre_frase = _frase_de_cierre(
        n_hechas=len(hechas),
        n_pendientes=len(pendientes_hoy),
    )

    resumen_corto = _resumen_corto_cierre(
        n_hechas=len(hechas),
        n_pendientes=len(pendientes_hoy),
        n_manana=len(tareas_manana) + len(eventos_manana_fmt),
    )

    texto_para_voz = _texto_voz_cierre(
        fecha_es=_fecha_es(ahora),
        hechas=hechas,
        pendientes_hoy=pendientes_hoy,
        tareas_manana=tareas_manana,
        eventos_manana=eventos_manana_fmt,
        cierre_frase=cierre_frase,
    )

    # Rollover de lo no cumplido: en el cierre revisamos lo que quedó y
    # proponemos cuándo retomarlo (al siguiente hueco), tocable. Nunca en
    # silencio. Best-effort: si falla, el cierre sale igual.
    try:
        from ..matix import rollover

        roll = await rollover.proponer_rollover(db, hasta_fin_de_hoy=True)
    except Exception:  # noqa: BLE001
        roll = {"proposals": [], "sobrecarga": rollover_sobrecarga_vacia()}

    # El cierre, hablado, también menciona lo no cumplido: nunca muere callado.
    # La acción tocable (mover/soltar) la resuelve el robot en Inicio.
    props = roll.get("proposals") or []
    sob = roll.get("sobrecarga") or {}
    if sob.get("sobrecargado") and sob.get("mensaje"):
        texto_para_voz += " " + sob["mensaje"]
    elif props:
        primero = props[0]
        cuando = (primero.get("propuesta") or {}).get("cuando")
        if cuando:
            texto_para_voz += (
                f" Quedó {primero['titulo']} sin hacer; te propongo retomarlo "
                f"{cuando}. Lo confirmas con un toque en Inicio."
            )
        else:
            texto_para_voz += (
                f" Quedó {primero['titulo']} sin hacer; cuando quieras lo "
                "reacomodamos."
            )

    return {
        "fecha": hoy.isoformat(),
        "dia_semana": _dia_semana_es(ahora),
        "saludo": "Buenas noches",
        "hechas": hechas,
        "pendientes_hoy": pendientes_hoy,
        "tareas_manana": tareas_manana,
        "eventos_manana": eventos_manana_fmt,
        "cierre_frase": cierre_frase,
        "resumen_corto": resumen_corto,
        "texto_para_voz": texto_para_voz,
        "rollover": roll,
    }


def rollover_sobrecarga_vacia() -> dict[str, Any]:
    """Sobrecarga 'sin nada' para el fallback del cierre si el rollover falla."""
    return {
        "sobrecargado": False, "n": 0, "peor_titulo": None,
        "peor_veces": 0, "mensaje": None, "recomendacion": None,
    }


def _frase_de_cierre(*, n_hechas: int, n_pendientes: int) -> str:
    """La línea 'para soltar'. Tono amable, nunca de reproche. Se
    adapta al volumen del día sin culpabilizar lo que quedó."""
    if n_hechas > 0 and n_pendientes == 0:
        return (
            "Cerraste todo lo que vencía hoy. Suelta el día y descansa."
        )
    if n_hechas > 0 and n_pendientes > 0:
        return (
            "Avanzaste hoy. Lo que quedó no se va a ningún lado — "
            "mañana sigues con la cabeza fresca."
        )
    if n_hechas == 0 and n_pendientes > 0:
        return (
            "Hoy no marcaste tareas y está perfecto. Mañana es otra "
            "oportunidad; por ahora, descansa."
        )
    return "Día tranquilo. Deja ir lo que no dependía de ti y descansa."


def _resumen_corto_cierre(
    *, n_hechas: int, n_pendientes: int, n_manana: int
) -> str:
    """Cuerpo de la notificación nocturna."""
    partes: list[str] = []
    if n_hechas:
        partes.append(
            f"{n_hechas} {'hecha' if n_hechas == 1 else 'hechas'}"
        )
    if n_pendientes:
        partes.append(
            f"{n_pendientes} {'pendiente' if n_pendientes == 1 else 'pendientes'}"
        )
    if n_manana:
        partes.append(f"{n_manana} para mañana")
    if not partes:
        return "Repaso del día"
    return " · ".join(partes)


def _texto_voz_cierre(
    *,
    fecha_es: str,
    hechas: list[dict[str, Any]],
    pendientes_hoy: list[dict[str, Any]],
    tareas_manana: list[dict[str, Any]],
    eventos_manana: list[dict[str, Any]],
    cierre_frase: str,
) -> str:
    """Prosa continua para TTS. Frases cortas, sin markdown, tono de
    cierre."""
    frases: list[str] = [f"Buenas noches. Cierre del {fecha_es}."]

    if hechas:
        n = len(hechas)
        if n == 1:
            frases.append(f"Hoy completaste: {hechas[0]['titulo']}.")
        else:
            frases.append(f"Hoy completaste {n} tareas.")
            for h in hechas[:4]:
                frases.append(f"{h['titulo']}.")
    else:
        frases.append("Hoy no marcaste tareas completadas.")

    if pendientes_hoy:
        n = len(pendientes_hoy)
        if n == 1:
            frases.append(f"Quedó pendiente: {pendientes_hoy[0]['titulo']}.")
        else:
            frases.append(f"Quedaron {n} pendientes de hoy.")

    total_manana = len(tareas_manana) + len(eventos_manana)
    if total_manana:
        frases.append("Para mañana:")
        for e in eventos_manana[:3]:
            if e["todo_el_dia"]:
                frases.append(f"Todo el día, {e['titulo']}.")
            else:
                frases.append(f"A las {e['hora']}, {e['titulo']}.")
        for t in tareas_manana[:3]:
            frases.append(f"Vence {t['titulo']}.")

    frases.append(cierre_frase)
    return " ".join(frases)
