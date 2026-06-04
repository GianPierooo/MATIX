"""Arma el contexto vivo del hub que se le pasa a Matix antes de
cada turno.

Contenido: proyectos activos con acción siguiente, tareas de hoy,
vencidas, eventos del día, próximas evaluaciones, último cierre del
día. Sin IA — solo lectura del CRUD existente.

El contexto se concatena al system prompt en el orquestador, pero
**aparte de la parte cacheable**, porque cambia cada turno y rompería
el caching si fuera al inicio.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

from ..db import Postgrest


def _ahora_lima() -> datetime:
    """Hora actual en Lima (UTC-5). El cerebro no asume el sistema en
    UTC ni el reloj local; lo calcula explícito."""
    return datetime.now(timezone.utc).astimezone(
        timezone(timedelta(hours=-5))
    )


def _formato_hora(ts: str | None) -> str:
    if ts is None:
        return "—"
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        lima = dt.astimezone(timezone(timedelta(hours=-5)))
        return lima.strftime("%H:%M")
    except Exception:
        return ts


def _formato_fecha(ts: str | None) -> str:
    if ts is None:
        return "sin fecha"
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        lima = dt.astimezone(timezone(timedelta(hours=-5)))
        return lima.strftime("%a %d %b %H:%M")
    except Exception:
        return ts


async def contexto_vivo(db: Postgrest) -> str:
    """Devuelve un bloque de markdown con la foto del hub ahora."""
    ahora = _ahora_lima()
    hoy = ahora.date()
    fin_hoy = (
        ahora.replace(hour=23, minute=59, second=59)
        .astimezone(timezone.utc)
        .isoformat()
    )
    ini_hoy = (
        ahora.replace(hour=0, minute=0, second=0)
        .astimezone(timezone.utc)
        .isoformat()
    )

    # ── Proyectos activos
    proyectos = await db.list(
        "proyectos", filters={"estado": "activo"}
    )
    proyectos.sort(key=lambda p: p.get("prioridad") or 99)

    # ── Todas las tareas (filtramos en cliente).
    # Excluimos la papelera: Matix no debe ver lo que el usuario borró.
    tareas = await db.list(
        "tareas", raw_filters={"eliminado_en": "is.null"}
    )
    tareas_hoy = []
    vencidas = []
    completadas_hoy = []  # para reabrir_tarea
    for t in tareas:
        if t.get("completada"):
            # Solo nos interesan las que se completaron HOY (en Lima),
            # para que Matix pueda deshacerlo si fue un error reciente.
            ce = t.get("completada_en")
            if not ce:
                continue
            try:
                ce_dt = datetime.fromisoformat(ce.replace("Z", "+00:00"))
                ce_lima = ce_dt.astimezone(timezone(timedelta(hours=-5)))
            except Exception:
                continue
            if ce_lima.date() == hoy:
                completadas_hoy.append(t)
            continue
        v = t.get("vence_en")
        if not v:
            continue
        try:
            v_dt = datetime.fromisoformat(v.replace("Z", "+00:00"))
            v_lima = v_dt.astimezone(timezone(timedelta(hours=-5)))
        except Exception:
            continue
        if v_lima.date() == hoy:
            tareas_hoy.append(t)
        elif v_lima.date() < hoy:
            vencidas.append(t)
    # Ordenamos las completadas por hora de cierre descendente (la
    # última primero, que suele ser la que el usuario quiere deshacer).
    completadas_hoy.sort(
        key=lambda t: t.get("completada_en") or "",
        reverse=True,
    )

    # ── Eventos de hoy (sin papelera).
    eventos = await db.list(
        "eventos", raw_filters={"eliminado_en": "is.null"}
    )
    eventos_hoy = []
    for e in eventos:
        ini = e.get("inicia_en")
        if not ini:
            continue
        try:
            i_dt = datetime.fromisoformat(ini.replace("Z", "+00:00"))
            i_lima = i_dt.astimezone(timezone(timedelta(hours=-5)))
        except Exception:
            continue
        if i_lima.date() == hoy:
            eventos_hoy.append(e)
    eventos_hoy.sort(key=lambda e: e["inicia_en"])

    # ── Próximas evaluaciones (las 5 más cercanas, no calificadas)
    evals = await db.list("evaluaciones")
    futuras = []
    for ev in evals:
        if ev.get("nota_obtenida") is not None:
            continue
        f = ev.get("fecha")
        if not f or f < ini_hoy:
            continue
        futuras.append(ev)
    futuras.sort(key=lambda x: x["fecha"])
    futuras = futuras[:5]

    # ── Tracks de aprendizaje activos (Fase 2)
    tracks_activos = await db.list("tracks", filters={"estado": "activo"})
    tracks_activos.sort(key=lambda t: t.get("creado_en") or "")

    # ── Último cierre del día
    cierres = await db.list("cierres_dia", order="fecha.desc", limit=1)

    # ── Sesiones de clase de hoy
    sesiones = await db.list("sesiones_clase")
    dia_semana = (ahora.weekday())  # L=0..D=6
    sesiones_hoy = [s for s in sesiones if s["dia_semana"] == dia_semana]
    sesiones_hoy.sort(key=lambda s: s["hora_inicio"])

    # ── Mapa curso_id → nombre
    cursos = await db.list("cursos")
    nombre_curso = {c["id"]: c["nombre"] for c in cursos}

    # ── Mapa proyecto_id → nombre (para tareas)
    nombre_proyecto = {p["id"]: p["nombre"] for p in proyectos}
    # también incluir aparcados/terminados para acción siguiente
    todos_proyectos = await db.list("proyectos")
    nombre_proyecto.update(
        {p["id"]: p["nombre"] for p in todos_proyectos}
    )

    # ── Mapa tarea_id → titulo (para acción siguiente)
    titulo_tarea = {t["id"]: t["titulo"] for t in tareas}

    # ─────── Formato markdown ───────
    lineas: list[str] = []
    lineas.append(
        f"## Contexto vivo del hub — {ahora.strftime('%A %d de %B de %Y, %H:%M')}"
    )
    lineas.append("")

    # Proyectos activos (de TRABAJO) y skills/hábitos van por separado: las
    # skills no consumen el tope de 3 y se dosifican ligero (no se marcan en
    # riesgo ni se insiste como una tarea comprometida).
    proyectos_trabajo = [p for p in proyectos if not p.get("es_skill")]
    skills = [p for p in proyectos if p.get("es_skill")]

    lineas.append("### Proyectos activos")
    if proyectos_trabajo:
        for p in proyectos_trabajo:
            prio = p.get("prioridad") or "?"
            linea = f"- **#{prio} {p['nombre']}**  `id={p['id']}`"
            if p.get("linea_meta"):
                linea += f" — meta: «{p['linea_meta']}»"
            if p.get("tarea_siguiente_id"):
                tarea_nom = titulo_tarea.get(p["tarea_siguiente_id"])
                if tarea_nom:
                    linea += (
                        f" — acción siguiente: «{tarea_nom}»  "
                        f"`tarea_id={p['tarea_siguiente_id']}`"
                    )
            # calor
            try:
                ult = datetime.fromisoformat(
                    p["ultima_actividad_en"].replace("Z", "+00:00")
                )
                dias = (datetime.now(timezone.utc) - ult).days
                if dias >= 3:
                    linea += f" · ⚠ EN RIESGO ({dias}d sin avance)"
            except Exception:
                pass
            lineas.append(linea)
    else:
        lineas.append("- (ninguno)")
    lineas.append("")

    if skills:
        lineas.append("### Skills / hábitos (dosis ligera, NO cuentan en el tope de 3)")
        for p in skills:
            linea = f"- **{p['nombre']}**  `id={p['id']}`"
            obj = (p.get("objetivo") or p.get("linea_meta") or "").strip()
            if obj:
                linea += f" — {obj}"
            lineas.append(linea)
        lineas.append(
            "(Trátalas suave: ofrece el SIGUIENTE trozo digerible del bloque "
            "actual, nunca el currículo entero; celebra lo pequeño; no insistas.)"
        )
        lineas.append("")

    # Vencidas
    if vencidas:
        lineas.append(f"### Tareas vencidas ({len(vencidas)})")
        for t in vencidas[:10]:
            ctx = ""
            if t.get("proyecto_id"):
                p = nombre_proyecto.get(t["proyecto_id"])
                if p:
                    ctx = f" ({p})"
            elif t.get("curso_id"):
                c = nombre_curso.get(t["curso_id"])
                if c:
                    ctx = f" ({c})"
            lineas.append(
                f"- {t['titulo']}{ctx} · venció {_formato_fecha(t['vence_en'])}  "
                f"`id={t['id']}`"
            )
        lineas.append("")

    # Tareas completadas HOY — para que Matix pueda usar `reabrir_tarea`
    # si Gian Piero las marcó por error (típicamente vía voz).
    if completadas_hoy:
        lineas.append(
            f"### Tareas completadas hoy ({len(completadas_hoy)})"
        )
        for t in completadas_hoy[:10]:
            ctx = ""
            if t.get("proyecto_id"):
                p = nombre_proyecto.get(t["proyecto_id"])
                if p:
                    ctx = f" ({p})"
            elif t.get("curso_id"):
                c = nombre_curso.get(t["curso_id"])
                if c:
                    ctx = f" ({c})"
            lineas.append(
                f"- ✓ {t['titulo']}{ctx}  `id={t['id']}`"
            )
        lineas.append("")

    # Tareas hoy
    if tareas_hoy:
        lineas.append(f"### Tareas para hoy ({len(tareas_hoy)})")
        for t in tareas_hoy:
            ctx = ""
            if t.get("proyecto_id"):
                p = nombre_proyecto.get(t["proyecto_id"])
                if p:
                    ctx = f" ({p})"
            elif t.get("curso_id"):
                c = nombre_curso.get(t["curso_id"])
                if c:
                    ctx = f" ({c})"
            lineas.append(
                f"- {t['titulo']}{ctx} · {_formato_hora(t['vence_en'])} · "
                f"prioridad {t['prioridad']}  `id={t['id']}`"
            )
        lineas.append("")

    # Eventos hoy
    if eventos_hoy or sesiones_hoy:
        lineas.append("### Hoy en el calendario")
        for s in sesiones_hoy:
            curso = nombre_curso.get(s["curso_id"], "Clase")
            lineas.append(
                f"- {s['hora_inicio'][:5]}–{s['hora_fin'][:5]}  "
                f"{curso} (clase semanal)"
            )
        for e in eventos_hoy:
            lineas.append(
                f"- {_formato_hora(e['inicia_en'])}"
                + (
                    f"–{_formato_hora(e.get('termina_en'))}"
                    if e.get("termina_en")
                    else ""
                )
                + f"  {e['titulo']}"
            )
        lineas.append("")

    # Tracks de aprendizaje activos (Fase 2) — para que Matix sepa qué
    # está aprendiendo y en qué bloque va ("vas en el bloque 3 de
    # calistenia, hoy toca…").
    if tracks_activos:
        lineas.append("### Tracks de aprendizaje activos")
        for t in tracks_activos:
            pos = t.get("bloque_actual") or "sin posición"
            extra = ""
            if t.get("semana") is not None:
                extra += f", semana {t['semana']}"
            if t.get("dia") is not None:
                extra += f", día {t['dia']}"
            linea = f"- **{t['nombre']}** — {pos}{extra}  `id={t['id']}`"
            if t.get("descripcion"):
                linea += f" · {t['descripcion']}"
            lineas.append(linea)
        lineas.append("")

    # Próximas evaluaciones
    if futuras:
        lineas.append("### Próximas evaluaciones")
        for ev in futuras:
            curso = nombre_curso.get(ev["curso_id"], "Curso")
            lineas.append(
                f"- {curso} · {ev['titulo']} ({ev['tipo']}) · "
                f"{_formato_fecha(ev['fecha'])}"
            )
        lineas.append("")

    # Último cierre
    if cierres:
        c = cierres[0]
        if c["fecha"] != date.today().isoformat():
            lineas.append(f"### Último cierre del día ({c['fecha']})")
            for item in c.get("items", []):
                lineas.append(f"- {item}")
            if c.get("nota_extra"):
                lineas.append(f"- _nota:_ {c['nota_extra']}")
            lineas.append("")

    # Cursos (siempre incluido para que Matix pueda asociar tareas/eventos)
    if cursos:
        lineas.append("### Cursos (referencia de ids)")
        for c in cursos:
            lineas.append(f"- {c['nombre']}  `id={c['id']}`")
        lineas.append("")

    if len(lineas) <= 2:
        lineas.append("_El hub está vacío._")
    return "\n".join(lineas)
