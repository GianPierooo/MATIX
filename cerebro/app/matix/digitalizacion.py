"""Digitalización por cámara (Capa 7) — creación de lo CONFIRMADO.

La cámara es UN CLIENTE MÁS de la capa de comandos: lo que el usuario revisó y
confirmó (la propuesta que devolvió `llm.extraer_documento_json`) se crea SIEMPRE
por los comandos canónicos de Fases 1-5 — `crear_tarea`, `crear_evento`,
`crear_curso`, `crear_sesion_clase`, `crear_evaluacion` — vía el registro. No hay
una ruta de creación paralela.

CONFIRMACIÓN ANTES DE CREAR: este módulo SOLO corre con la propuesta ya
confirmada por el usuario (la extracción y la creación son endpoints separados;
la app muestra el preview y solo entonces llama a crear). Best-effort por ítem:
un fallo no tumba a los demás; se reportan `creados` y `errores`.

Apuntes: NO tienen comando en el registro todavía (gap de Fase 6), así que se
crean igual que su router — `insert` + indexado RAG best-effort. El resto pasa
por el comando.
"""
from __future__ import annotations

from typing import Any

from ..comandos import registro
from ..db import Postgrest

# Offset fijo de Lima (UTC-5, sin DST) para componer timestamps ISO.
_LIMA_OFFSET = "-05:00"


def _inicia_iso(fecha: str, hora: str | None) -> str:
    """Combina fecha (YYYY-MM-DD) + hora (HH:MM) en ISO 8601 con offset Lima."""
    return f"{fecha}T{(hora or '00:00')}:00{_LIMA_OFFSET}"


async def crear_desde_captura(db: Postgrest, propuesta: dict[str, Any]) -> dict[str, Any]:
    """Crea lo confirmado por los comandos canónicos. Devuelve {creados, errores}.

    `propuesta` es la salida (editada/confirmada por el usuario) de
    `extraer_documento_json`: {tareas, cursos, eventos, apunte}."""
    creados: list[dict[str, Any]] = []
    errores: list[dict[str, Any]] = []

    async def _cmd(nombre: str, params: dict, etiqueta: str) -> dict | None:
        res = await registro.ejecutar(db, nombre, params, origen="camara")
        if res.get("ok"):
            d = res["datos"]
            creados.append({"tipo": nombre, "id": d.get("id"), "titulo": d.get("titulo") or d.get("nombre")})
            return d
        errores.append({"tipo": nombre, "titulo": etiqueta, "mensaje": res.get("mensaje", "no se pudo")})
        return None

    # ── Tareas → crear_tarea ──────────────────────────────────────────────────
    for t in propuesta.get("tareas") or []:
        if not isinstance(t, dict) or not t.get("titulo"):
            continue
        params = {"titulo": t["titulo"]}
        if t.get("vence_en"):
            params["vence_en"] = t["vence_en"]  # Pydantic coacciona la fecha
        await _cmd("crear_tarea", params, t["titulo"])

    # ── Cursos (sílabo/horario) → crear_curso + sus sesiones y evaluaciones ───
    for c in propuesta.get("cursos") or []:
        if not isinstance(c, dict) or not c.get("nombre"):
            continue
        curso = await _cmd(
            "crear_curso",
            {"nombre": c["nombre"], **({"profesor": c["profesor"]} if c.get("profesor") else {})},
            c["nombre"],
        )
        if curso is None:
            continue  # sin curso no podemos colgar sesiones/evaluaciones
        cid = str(curso["id"])
        for s in c.get("sesiones") or []:
            if not isinstance(s, dict) or "dia_semana" not in s or not s.get("hora_inicio"):
                continue
            params = {"curso_id": cid, "dia_semana": s["dia_semana"], "hora_inicio": s["hora_inicio"]}
            if s.get("hora_fin"):
                params["hora_fin"] = s["hora_fin"]
            else:
                # SesionClaseCreate exige hora_fin > hora_inicio; default +1h si no vino.
                hi = str(s["hora_inicio"])
                try:
                    h, m = int(hi[:2]), int(hi[3:5])
                    params["hora_fin"] = f"{(h + 1) % 24:02d}:{m:02d}"
                except (ValueError, IndexError):
                    params["hora_fin"] = s["hora_inicio"]
            await _cmd("crear_sesion_clase", params, f"{c['nombre']} (clase)")
        for ev in c.get("evaluaciones") or []:
            if not isinstance(ev, dict) or not ev.get("titulo") or not ev.get("fecha"):
                continue
            params = {
                "curso_id": cid, "titulo": ev["titulo"],
                "tipo": ev.get("tipo") or "otro", "fecha": ev["fecha"],
            }
            if ev.get("peso") is not None:
                params["peso"] = ev["peso"]
            await _cmd("crear_evaluacion", params, ev["titulo"])

    # ── Eventos sueltos → crear_evento ────────────────────────────────────────
    for e in propuesta.get("eventos") or []:
        if not isinstance(e, dict) or not e.get("titulo") or not e.get("fecha"):
            continue
        params: dict[str, Any] = {
            "titulo": e["titulo"],
            "inicia_en": _inicia_iso(e["fecha"], e.get("hora_inicio")),
            "todo_el_dia": not e.get("hora_inicio"),
        }
        if e.get("hora_fin"):
            params["termina_en"] = _inicia_iso(e["fecha"], e["hora_fin"])
        await _cmd("crear_evento", params, e["titulo"])

    # ── Apunte → insert + indexado RAG (no hay comando de apuntes todavía) ────
    ap = propuesta.get("apunte")
    if isinstance(ap, dict) and ap.get("titulo"):
        try:
            fila = await db.insert("apuntes", {
                "titulo": ap["titulo"],
                "contenido": ap.get("contenido") or "",
            })
            creados.append({"tipo": "crear_apunte", "id": fila.get("id"), "titulo": fila.get("titulo")})
            try:
                from .indexador import indexar_apunte

                await indexar_apunte(db, fila)
            except Exception:  # noqa: BLE001 — el apunte ya quedó; el RAG se reintenta luego
                pass
        except Exception as e:  # noqa: BLE001
            errores.append({"tipo": "crear_apunte", "titulo": ap["titulo"], "mensaje": f"{type(e).__name__}"})

    return {"creados": creados, "errores": errores, "total": len(creados)}
