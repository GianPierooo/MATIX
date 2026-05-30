"""Arma el repaso semanal con Matix (Capa 8 · Repaso).

Es el cierre del día pero SEMANAL y más estratégico: revisa qué se hizo,
qué se quedó, y qué priorizar la próxima semana — leyendo el hub de los
últimos 7 días. A diferencia del briefing/cierre (plantillas
determinísticas), acá Matix SINTETIZA con el LLM. Si el modelo no está
disponible, caemos a un resumen determinístico — el repaso nunca se
queda mudo.

Tono: balance honesto, sin reproche. Reconoce lo hecho, nombra lo que
quedó sin drama, sugiere 1–3 focos.

Devuelve, además del texto sintetizado, las tareas que se pasaron de
fecha CON su id, para que la app permita reprogramarlas desde el repaso.
"""
from __future__ import annotations

import logging
from datetime import timedelta
from typing import Any

from ..db import Postgrest
from ..matix import llm
from .armar import _a_lima, _ahora_lima

logger = logging.getLogger("matix.repaso")

_VENTANA_DIAS = 7
_TOPE_VENCIDAS = 15


def _contexto(
    t: dict[str, Any],
    nombre_proyecto: dict[str, str],
    nombre_curso: dict[str, str],
) -> str | None:
    if t.get("proyecto_id"):
        return nombre_proyecto.get(t["proyecto_id"])
    if t.get("curso_id"):
        return nombre_curso.get(t["curso_id"])
    return None


async def armar_repaso(db: Postgrest) -> dict[str, Any]:
    ahora = _ahora_lima()
    hoy = ahora.date()
    desde = hoy - timedelta(days=_VENTANA_DIAS - 1)  # 7 días incluyendo hoy

    tareas = await db.list("tareas", raw_filters={"eliminado_en": "is.null"})
    proyectos = await db.list("proyectos")
    cursos = await db.list("cursos")
    nombre_proyecto = {p["id"]: p["nombre"] for p in proyectos}
    nombre_curso = {c["id"]: c["nombre"] for c in cursos}

    completadas = 0
    vencidas: list[dict[str, Any]] = []
    for t in tareas:
        if t.get("completada"):
            ce = _a_lima(t.get("completada_en"))
            if ce and desde <= ce.date() <= hoy:
                completadas += 1
            continue
        v = _a_lima(t.get("vence_en"))
        if v and v.date() < hoy:
            vencidas.append(
                {
                    "id": t["id"],
                    "titulo": t["titulo"],
                    "contexto": _contexto(t, nombre_proyecto, nombre_curso),
                    "vence_en": t.get("vence_en"),
                }
            )
    vencidas.sort(key=lambda x: x.get("vence_en") or "")
    vencidas = vencidas[:_TOPE_VENCIDAS]

    # Eventos que hubo en la ventana.
    eventos_raw = await db.list(
        "eventos", raw_filters={"eliminado_en": "is.null"}
    )
    eventos = 0
    for e in eventos_raw:
        ini = _a_lima(e.get("inicia_en"))
        if ini and desde <= ini.date() <= hoy:
            eventos += 1

    # Proyectos activos + riesgo.
    proyectos_activos = []
    for p in proyectos:
        if p.get("estado") != "activo":
            continue
        ult = _a_lima(p.get("ultima_actividad_en"))
        dias = (ahora - ult).days if ult else None
        proyectos_activos.append(
            {
                "nombre": p["nombre"],
                "dias_sin_avance": dias,
                "en_riesgo": dias is not None and dias >= 3,
            }
        )

    # Apuntes capturados en la ventana.
    apuntes_raw = await db.list(
        "apuntes", raw_filters={"eliminado_en": "is.null"}
    )
    apuntes_nuevos = 0
    titulos_apuntes: list[str] = []
    for a in apuntes_raw:
        ce = _a_lima(a.get("creado_en"))
        if ce and desde <= ce.date() <= hoy:
            apuntes_nuevos += 1
            if len(titulos_apuntes) < 6:
                titulos_apuntes.append(a.get("titulo", ""))

    # Resumen compacto para el LLM (sin ids ni ruido).
    datos = {
        "dias": _VENTANA_DIAS,
        "tareas_completadas": completadas,
        "tareas_que_se_pasaron": [
            {"titulo": v["titulo"], "contexto": v["contexto"]}
            for v in vencidas
        ],
        "eventos_que_hubo": eventos,
        "proyectos_activos": proyectos_activos,
        "apuntes_capturados": apuntes_nuevos,
        "titulos_apuntes": titulos_apuntes,
    }

    resumen, focos = await _sintetizar(datos, len(vencidas))

    return {
        "semana_desde": desde.isoformat(),
        "semana_hasta": hoy.isoformat(),
        "resumen": resumen,
        "focos": focos,
        "completadas": completadas,
        "vencidas": vencidas,
        "eventos": eventos,
        "apuntes_nuevos": apuntes_nuevos,
    }


async def _sintetizar(
    datos: dict[str, Any], n_vencidas: int
) -> tuple[str, list[str]]:
    """Pide al LLM el resumen + focos. Si falla (sin API key, sin red,
    JSON inválido), cae a un resumen determinístico honesto."""
    try:
        out = await llm.repaso_semanal_json(datos)
        return out["resumen"], out["focos"]
    except Exception as e:  # noqa: BLE001
        logger.warning("repaso semanal: LLM no disponible (%s)", type(e).__name__)
        return _fallback(
            completadas=datos["tareas_completadas"],
            n_vencidas=n_vencidas,
            eventos=datos["eventos_que_hubo"],
        )


def _fallback(
    *, completadas: int, n_vencidas: int, eventos: int
) -> tuple[str, list[str]]:
    partes: list[str] = []
    if completadas:
        partes.append(
            f"Esta semana cerraste {completadas} "
            f"{'tarea' if completadas == 1 else 'tareas'}"
        )
    else:
        partes.append("Esta semana no marcaste tareas completadas, y está bien")
    if eventos:
        partes.append(
            f"tuviste {eventos} {'evento' if eventos == 1 else 'eventos'}"
        )
    if n_vencidas:
        partes.append(
            f"{n_vencidas} {'quedó' if n_vencidas == 1 else 'quedaron'} "
            "sin cerrar — las puedes reprogramar sin drama"
        )
    resumen = ". ".join(partes) + "."

    focos: list[str] = []
    if n_vencidas:
        focos.append("Reprograma o suelta lo que se pasó de fecha.")
    focos.append("Elige 1–3 cosas que de verdad importen para esta semana.")
    return resumen, focos[:3]
