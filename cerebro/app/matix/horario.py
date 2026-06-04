"""Capa de horario: del set priorizado del día a un plan colocado en el tiempo.

Lee los compromisos FIJOS (clases de uni en `sesiones_clase`, gym y demás
recurrentes en `eventos`) + las ANCLAS editables (`config_horario`), calcula las
VENTANAS libres reales (dentro de despertar/dormir, con buffers cortos alrededor
de lo fijo) y COLOCA ahí el set del día (que ya produce el motor de evolución,
priorizado y ajustado al ritmo) más slots ligeros de skills y tareas puntuales.

Reglas (anti-amontone, honesto):
- Lo más importante/difícil va en el bloque PICO (mañana).
- Skills/tareas puntuales en ventanas más LIGERAS (no roban el pico).
- Buffers entre bloques; estructura fuerte pero TENTATIVA (ajustable).
- Si no entra, RECORTA por prioridad y reporta qué quedó fuera — no amontona.
- No agenda nada pasado el ancla de dormir; respeta el silencio.
- Reusa la adaptación de ritmo: el set que entra ya viene recortado si vienes
  atrasado (planificador_diario), así que acá no se "rellena" de más.

La parte PURA (ventanas, colocación, recorte, pico, buffers, recurrencia) está
separada y se testea sin BD.
"""
from __future__ import annotations

from datetime import date, datetime, timezone
from typing import Any
from zoneinfo import ZoneInfo

from ..db import Postgrest
from . import creacion_proyecto

LIMA = ZoneInfo("America/Lima")

# Defaults si aún no hay fila de config_horario (el planner funciona igual).
_CFG_DEFAULT: dict[str, Any] = {
    "hora_despertar": 7,
    "hora_dormir": 23,
    "pico_inicio": 6,
    "pico_fin": 9,
    "buffer_min": 10,
    "dur_trabajo_min": 90,
    "dur_skill_min": 30,
    "dur_tarea_min": 20,
    "anclas": [{"titulo": "Calistenia", "inicio": "07:00", "fin": "07:45",
                "dias": [1, 2, 3, 4, 5, 6, 7]}],
}


# ════════════════════════════════════════════════════════════════════════════
# LÓGICA PURA (testeable sin BD) — todo en minutos desde medianoche (hora Lima)
# ════════════════════════════════════════════════════════════════════════════

def hhmm_a_min(s: str) -> int | None:
    """'HH:MM' → minutos desde medianoche. None si no parsea. PURO."""
    try:
        h, m = str(s).strip()[:5].split(":")
        return int(h) * 60 + int(m)
    except (ValueError, AttributeError):
        return None


def min_a_hhmm(m: int) -> str:
    """Minutos → 'HH:MM' (acota 0..1439). PURO."""
    m = max(0, min(24 * 60 - 1, int(m)))
    return f"{m // 60:02d}:{m % 60:02d}"


def ocurre_en(evento: dict[str, Any], fecha: date) -> bool:
    """¿Este evento cae en `fecha`? Maneja eventos sueltos y recurrentes
    (diaria/semanal/mensual) con su fin (nunca/hasta/conteo). PURO.

    Expande la recurrencia que en la BD vive solo como REGLA (no materializada)."""
    ini = _parse_dt(evento.get("inicia_en"))
    if ini is None:
        return False
    ini_d = ini.astimezone(LIMA).date()
    freq = (evento.get("recurrencia_freq") or "").strip().lower()
    if not freq:
        return ini_d == fecha
    if fecha < ini_d:
        return False
    fin_tipo = (evento.get("recurrencia_fin_tipo") or "").strip().lower()
    if fin_tipo == "hasta":
        hasta = _parse_date(evento.get("recurrencia_hasta"))
        if hasta and fecha > hasta:
            return False

    if freq == "diaria":
        cae = True
    elif freq == "semanal":
        dias = evento.get("recurrencia_dias_semana") or [ini.astimezone(LIMA).isoweekday()]
        cae = fecha.isoweekday() in dias
    elif freq == "mensual":
        cae = fecha.day == ini_d.day
    else:
        cae = False
    if not cae:
        return False

    if fin_tipo == "conteo":
        conteo = evento.get("recurrencia_conteo")
        if conteo:
            if _ordinal_ocurrencia(freq, evento.get("recurrencia_dias_semana"), ini_d, fecha) > int(conteo):
                return False
    return True


def fusionar_ocupados(
    compromisos: list[dict[str, Any]], *, buffer_min: int
) -> list[tuple[int, int]]:
    """Toma los rangos ocupados (fijos), les pone un buffer a cada lado y fusiona
    los que se solapan. Devuelve [(ini,fin)] ordenado. PURO."""
    rangos = []
    for c in compromisos:
        ini = c.get("ini_min")
        fin = c.get("fin_min")
        if ini is None or fin is None or fin <= ini:
            continue
        rangos.append((max(0, ini - buffer_min), fin + buffer_min))
    rangos.sort()
    fusion: list[tuple[int, int]] = []
    for ini, fin in rangos:
        if fusion and ini <= fusion[-1][1]:
            fusion[-1] = (fusion[-1][0], max(fusion[-1][1], fin))
        else:
            fusion.append((ini, fin))
    return fusion


def ventanas_libres(
    compromisos: list[dict[str, Any]],
    *,
    despertar_min: int,
    dormir_min: int,
    buffer_min: int,
    desde_min: int | None = None,
) -> list[dict[str, int]]:
    """Huecos reales del día dentro de [despertar, dormir], restando lo fijo (con
    buffer). Si `desde_min` (replan desde ahora), recorta lo anterior. NUNCA pasa
    de `dormir_min`. PURO."""
    inicio = despertar_min if desde_min is None else max(despertar_min, desde_min)
    if inicio >= dormir_min:
        return []
    ocupados = fusionar_ocupados(compromisos, buffer_min=buffer_min)
    libres: list[dict[str, int]] = []
    cursor = inicio
    for oi, of in ocupados:
        if of <= cursor:
            continue
        if oi > cursor:
            fin = min(oi, dormir_min)
            if fin > cursor:
                libres.append({"ini": cursor, "fin": fin, "dur": fin - cursor})
        cursor = max(cursor, of)
        if cursor >= dormir_min:
            break
    if cursor < dormir_min:
        libres.append({"ini": cursor, "fin": dormir_min, "dur": dormir_min - cursor})
    return [v for v in libres if v["dur"] > 0]


def es_pico(ventana: dict[str, int], pico_ini: int, pico_fin: int) -> bool:
    """¿La ventana toca el bloque pico? PURO."""
    return ventana["ini"] < pico_fin and ventana["fin"] > pico_ini


def colocar(
    items: list[dict[str, Any]],
    ventanas: list[dict[str, int]],
    *,
    buffer_min: int,
    pico_ini: int,
    pico_fin: int,
) -> dict[str, list[dict[str, Any]]]:
    """Coloca los `items` (YA ordenados por prioridad: trabajo importante primero,
    skills/tareas al final) en las `ventanas`. Reglas:
    - El PRIMER bloque de trabajo va al pico (lo más importante en prime time).
    - skills/tareas prefieren ventanas NO-pico (no roban el trabajo profundo).
    - Buffer entre bloques de la misma ventana.
    - Lo que no entra se RECORTA y va a `fuera` (capacidad honesta, no amontona).
    PURO. No muta `ventanas` (trabaja sobre copias)."""
    libres = [dict(v) for v in sorted(ventanas, key=lambda v: v["ini"])]
    bloques: list[dict[str, Any]] = []
    fuera: list[dict[str, Any]] = []
    primer_trabajo = True

    for item in items:
        dur = int(item["dur"])
        es_trabajo = item.get("tipo") == "trabajo"
        forzar_pico = es_trabajo and primer_trabajo

        cabe = [v for v in libres if (v["fin"] - v["ini"]) >= dur]
        if not cabe:
            fuera.append({**item, "motivo": "no entró en las ventanas de hoy"})
            continue

        if forzar_pico:
            pico = [v for v in cabe if es_pico(v, pico_ini, pico_fin)]
            elegida = pico[0] if pico else cabe[0]
        elif es_trabajo:
            elegida = cabe[0]  # earliest-fit
        else:  # skill / tarea: preferir ventanas ligeras (no-pico)
            no_pico = [v for v in cabe if not es_pico(v, pico_ini, pico_fin)]
            elegida = no_pico[0] if no_pico else cabe[0]

        ini = elegida["ini"]
        bloques.append({
            "ini_min": ini, "fin_min": ini + dur,
            "titulo": item["titulo"], "tipo": item["tipo"],
            "proyecto": item.get("proyecto"), "skill": item.get("skill"),
            "nodo_id": item.get("nodo_id"), "tarea_id": item.get("tarea_id"),
            "set_item_id": item.get("set_item_id"),
            "tentativo": True,
        })
        # Buffer antes del siguiente bloque colocado en la misma ventana.
        elegida["ini"] = ini + dur + buffer_min
        if es_trabajo:
            primer_trabajo = False

    bloques.sort(key=lambda b: b["ini_min"])
    return {"bloques": bloques, "fuera": fuera}


# ── Helpers de recurrencia / fechas (puros) ──────────────────────────────────

def _ordinal_ocurrencia(freq: str, dias_semana: Any, inicio: date, fecha: date) -> int:
    """Número de ocurrencia (1-based) de `fecha` desde `inicio` para la regla, para
    chequear el fin por conteo. PURO."""
    if freq == "diaria":
        return (fecha - inicio).days + 1
    if freq == "semanal":
        dias = set(dias_semana or [inicio.isoweekday()])
        n = 0
        d = inicio
        while d <= fecha:
            if d.isoweekday() in dias:
                n += 1
            d = date.fromordinal(d.toordinal() + 1)
        return n
    if freq == "mensual":
        return (fecha.year - inicio.year) * 12 + (fecha.month - inicio.month) + 1
    return 1


def _parse_dt(valor: Any) -> datetime | None:
    if isinstance(valor, datetime):
        return valor if valor.tzinfo else valor.replace(tzinfo=timezone.utc)
    if not isinstance(valor, str) or not valor:
        return None
    try:
        d = datetime.fromisoformat(valor.replace("Z", "+00:00"))
    except ValueError:
        return None
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)


def _parse_date(valor: Any) -> date | None:
    if isinstance(valor, date) and not isinstance(valor, datetime):
        return valor
    if not isinstance(valor, str) or not valor:
        return None
    try:
        return date.fromisoformat(valor[:10])
    except ValueError:
        return None


def _min_evento(evento: dict[str, Any], clave: str) -> int | None:
    dt = _parse_dt(evento.get(clave))
    if dt is None:
        return None
    loc = dt.astimezone(LIMA)
    return loc.hour * 60 + loc.minute


# ════════════════════════════════════════════════════════════════════════════
# Orquestación (impura): lee las tablas existentes y arma el plan del día
# ════════════════════════════════════════════════════════════════════════════

async def _config(db: Postgrest) -> dict[str, Any]:
    try:
        filas = await db.list("config_horario", limit=1)
    except Exception:  # noqa: BLE001
        filas = []
    return {**_CFG_DEFAULT, **(filas[0] if filas else {})}


async def _compromisos_fijos(
    db: Postgrest, *, fecha: date, anclas: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """Clases de uni (sesiones_clase) + recurrentes/sueltos (eventos) + anclas,
    como rangos en minutos. NO duplica: lee de donde ya viven."""
    fijos: list[dict[str, Any]] = []

    # Clases de uni (dia_semana: 0=Lun..6=Dom).
    try:
        sesiones = await db.list("sesiones_clase")
    except Exception:  # noqa: BLE001
        sesiones = []
    cursos = {}
    if sesiones:
        try:
            cursos = {c["id"]: c.get("nombre", "Clase") for c in await db.list("cursos")}
        except Exception:  # noqa: BLE001
            cursos = {}
    dow = fecha.weekday()  # 0=Lun
    for s in sesiones:
        if s.get("dia_semana") != dow:
            continue
        ini = hhmm_a_min(s.get("hora_inicio") or "")
        fin = hhmm_a_min(s.get("hora_fin") or "")
        if ini is None or fin is None:
            continue
        fijos.append({"ini_min": ini, "fin_min": fin, "tipo": "clase",
                      "titulo": cursos.get(s.get("curso_id"), "Clase")})

    # Eventos (gym y demás): sueltos del día + recurrentes que caen hoy.
    try:
        eventos = await db.list("eventos", raw_filters={"eliminado_en": "is.null"})
    except Exception:  # noqa: BLE001
        eventos = []
    for e in eventos:
        if e.get("todo_el_dia"):
            continue  # no bloquea una franja horaria
        if not ocurre_en(e, fecha):
            continue
        ini = _min_evento(e, "inicia_en")
        if ini is None:
            continue
        fin = _min_evento(e, "termina_en")
        if fin is None or fin <= ini:
            fin = ini + 60  # sin término: asume 1h
        fijos.append({"ini_min": ini, "fin_min": fin, "tipo": "evento",
                      "titulo": e.get("titulo") or "Evento"})

    # Anclas editables (dias en ISO 1..7).
    iso = fecha.isoweekday()
    for a in anclas or []:
        if iso not in (a.get("dias") or [1, 2, 3, 4, 5, 6, 7]):
            continue
        ini = hhmm_a_min(a.get("inicio") or "")
        fin = hhmm_a_min(a.get("fin") or "")
        if ini is None or fin is None or fin <= ini:
            continue
        fijos.append({"ini_min": ini, "fin_min": fin, "tipo": "ancla",
                      "titulo": a.get("titulo") or "Ancla"})

    fijos.sort(key=lambda c: c["ini_min"])
    return fijos


async def _items_a_colocar(
    db: Postgrest, *, fecha: date, cfg: dict[str, Any], solo_pendientes: bool
) -> list[dict[str, Any]]:
    """Construye la cola priorizada: trabajo (set del día, por prioridad del
    proyecto) → tareas puntuales de hoy → skills (ligeras, opcionales, al final).
    El set ya viene recortado por ritmo (planificador_diario)."""
    items: list[dict[str, Any]] = []

    # Prioridad por proyecto (1..3; sin número = 9).
    try:
        proyectos = await db.list("proyectos")
    except Exception:  # noqa: BLE001
        proyectos = []
    prio = {p["id"]: (p.get("prioridad") or 9) for p in proyectos}

    # Trabajo: set del día (no 'saltado'; si replan, tampoco 'hecho').
    try:
        set_items = await db.list("set_diario_items", filters={"fecha": fecha.isoformat()}, order="orden.asc")
    except Exception:  # noqa: BLE001
        set_items = []
    set_tarea_ids = set()
    for s in set_items:
        if s.get("tarea_id"):
            set_tarea_ids.add(s["tarea_id"])
        estado = s.get("estado")
        if estado == "saltado":
            continue
        if solo_pendientes and estado == "hecho":
            continue
        items.append({
            "titulo": s["titulo"], "tipo": "trabajo",
            "dur": int(cfg["dur_trabajo_min"]),
            "prioridad": prio.get(s.get("proyecto_id"), 9),
            "orden": s.get("orden", 0),
            "proyecto_id": s.get("proyecto_id"), "nodo_id": s.get("nodo_id"),
            "tarea_id": s.get("tarea_id"), "set_item_id": s.get("id"),
            "proyecto": next((p.get("nombre") for p in proyectos if p["id"] == s.get("proyecto_id")), None),
        })

    # Tareas puntuales de hoy que NO son del set (vencen hoy, sin completar).
    try:
        tareas = await db.list("tareas", raw_filters={"eliminado_en": "is.null"})
    except Exception:  # noqa: BLE001
        tareas = []
    for t in tareas:
        if t.get("completada") or t.get("id") in set_tarea_ids:
            continue
        vence = _parse_dt(t.get("vence_en"))
        if vence is None or vence.astimezone(LIMA).date() != fecha:
            continue
        items.append({
            "titulo": t.get("titulo") or "Tarea", "tipo": "tarea",
            "dur": int(cfg["dur_tarea_min"]), "prioridad": 5, "orden": 100,
            "tarea_id": t.get("id"),
        })

    # Skills activas: slot chico opcional cada una (lo más ligero, va al final).
    skills = creacion_proyecto.solo_skills(
        [p for p in proyectos if p.get("estado") == "activo"]
    )
    for sk in skills:
        items.append({
            "titulo": f"Práctica: {sk['nombre']}", "tipo": "skill",
            "dur": int(cfg["dur_skill_min"]), "prioridad": 8, "orden": 200,
            "proyecto_id": sk["id"], "skill": sk["nombre"],
        })

    items.sort(key=lambda i: (i["prioridad"], i["orden"]))
    return items


async def plan_de_hoy_data(
    db: Postgrest, *, ahora: datetime | None = None, desde_ahora: bool = False
) -> dict[str, Any]:
    """Arma el plan del día como DATA estructurada (para la vista «Hoy» / chat /
    calendario). `desde_ahora=True` = replanifica el resto del día desde la hora
    actual. Determinista (se recalcula al vuelo; no se persiste un plan rancio)."""
    ahora = ahora or datetime.now(timezone.utc)
    local = ahora.astimezone(LIMA)
    fecha = local.date()
    cfg = await _config(db)

    despertar = int(cfg["hora_despertar"]) * 60
    dormir = int(cfg["hora_dormir"]) * 60
    buffer_min = int(cfg["buffer_min"])
    pico_ini = int(cfg["pico_inicio"]) * 60
    pico_fin = int(cfg["pico_fin"]) * 60

    fijos = await _compromisos_fijos(db, fecha=fecha, anclas=cfg.get("anclas") or [])
    desde_min = (local.hour * 60 + local.minute) if desde_ahora else None
    ventanas = ventanas_libres(
        fijos, despertar_min=despertar, dormir_min=dormir,
        buffer_min=buffer_min, desde_min=desde_min,
    )

    items = await _items_a_colocar(db, fecha=fecha, cfg=cfg, solo_pendientes=desde_ahora)
    colocado = colocar(items, ventanas, buffer_min=buffer_min, pico_ini=pico_ini, pico_fin=pico_fin)

    # Bloques fijos (no tentativos) + bloques colocados (tentativos), ordenados.
    bloques_fijos = [
        {"inicio": min_a_hhmm(c["ini_min"]), "fin": min_a_hhmm(c["fin_min"]),
         "titulo": c["titulo"], "tipo": c["tipo"], "tentativo": False, "_ini": c["ini_min"]}
        for c in fijos
        if desde_min is None or c["fin_min"] > desde_min  # en replan, solo lo que queda
    ]
    bloques_puestos = [
        {"inicio": min_a_hhmm(b["ini_min"]), "fin": min_a_hhmm(b["fin_min"]),
         "titulo": b["titulo"], "tipo": b["tipo"], "proyecto": b.get("proyecto"),
         "skill": b.get("skill"), "nodo_id": b.get("nodo_id"), "tarea_id": b.get("tarea_id"),
         "set_item_id": b.get("set_item_id"),
         "tentativo": True, "_ini": b["ini_min"]}
        for b in colocado["bloques"]
    ]
    bloques = sorted(bloques_fijos + bloques_puestos, key=lambda b: b["_ini"])
    for b in bloques:
        b.pop("_ini", None)

    fuera = [{"titulo": f["titulo"], "tipo": f["tipo"], "motivo": f["motivo"]}
             for f in colocado["fuera"]]

    return {
        "fecha": fecha.isoformat(),
        "despierta": min_a_hhmm(despertar),
        "duerme": min_a_hhmm(dormir),
        "desde": min_a_hhmm(desde_min) if desde_min is not None else None,
        "bloques": bloques,
        "fuera": fuera,
    }


# ── Acciones del loop principal (mutan el estado real, no un plan rancio) ─────

async def completar_bloque(
    db: Postgrest, *, tarea_id: str | None = None, nodo_id: str | None = None,
) -> dict[str, Any]:
    """Marca un bloque planificado como HECHO en el estado real: cierra el nodo
    del árbol (el % sube solo) y/o completa la tarea del hub, y sincroniza el set
    del día. Al recalcular el plan, ese bloque ya no aparece."""
    hecho = []
    if nodo_id:
        await db.update("arbol_nodos", nodo_id, {"estado": "hecho"})
        hecho.append("nodo")
    if tarea_id:
        ahora = datetime.now(timezone.utc).isoformat()
        await db.update("tareas", tarea_id, {"completada": True, "completada_en": ahora})
        from . import planificador_diario
        await planificador_diario.marcar_item_por_tarea(db, tarea_id=tarea_id, estado="hecho")
        hecho.append("tarea")
    return {"ok": True, "completado": hecho}


async def saltar_bloque(db: Postgrest, *, set_item_id: str) -> dict[str, Any]:
    """Salta un bloque del set (no hoy, sin culpa): lo marca 'saltado'. No vuelve
    a colocarse en el plan de hoy."""
    await db.update("set_diario_items", set_item_id, {"estado": "saltado"})
    return {"ok": True, "saltado": set_item_id}


def _hhmm_a_utc_iso(fecha: date, hhmm: str) -> str:
    """Combina fecha + 'HH:MM' (hora Lima) → ISO UTC, para crear el evento."""
    m = hhmm_a_min(hhmm) or 0
    dt = datetime(fecha.year, fecha.month, fecha.day, m // 60, m % 60, tzinfo=LIMA)
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


async def empujar_a_calendario(
    db: Postgrest,
    *,
    bloques: list[dict[str, Any]] | None = None,
    ahora: datetime | None = None,
) -> dict[str, Any]:
    """Crea los bloques PLANIFICADOS (tentativos) como eventos del calendario.

    Si la app pasa `bloques` (con las horas que ve, incluidas ediciones), se
    usan esos; si no, se recalcula el plan. Idempotente: si ya existe un evento
    de hoy con el mismo título y hora de inicio, lo OMITE (no duplica si lo
    empujas dos veces). Los fijos (clases, gym) ya viven en el calendario."""
    ahora = ahora or datetime.now(timezone.utc)
    fecha = ahora.astimezone(LIMA).date()
    if bloques is None:
        data = await plan_de_hoy_data(db, ahora=ahora)
        bloques = [b for b in data["bloques"] if b.get("tentativo")]

    # Índice de lo que ya hay hoy (para no duplicar).
    try:
        eventos = await db.list("eventos", raw_filters={"eliminado_en": "is.null"})
    except Exception:  # noqa: BLE001
        eventos = []
    existentes = set()
    for e in eventos:
        dt = _parse_dt(e.get("inicia_en"))
        if dt and dt.astimezone(LIMA).date() == fecha:
            existentes.add((e.get("titulo"), dt.astimezone(LIMA).strftime("%H:%M")))

    creados, omitidos = 0, 0
    for b in bloques:
        titulo = (b.get("titulo") or "").strip()
        inicio = (b.get("inicio") or "").strip()
        if not titulo or not inicio:
            continue
        clave = (titulo, inicio)
        if clave in existentes:
            omitidos += 1
            continue
        fin = (b.get("fin") or "").strip() or min_a_hhmm((hhmm_a_min(inicio) or 0) + 30)
        await db.insert("eventos", {
            "titulo": titulo,
            "inicia_en": _hhmm_a_utc_iso(fecha, inicio),
            "termina_en": _hhmm_a_utc_iso(fecha, fin),
            "color": "#E0A33A",  # ámbar = tentativo
            "descripcion": "Bloque del plan de hoy (tentativo).",
        })
        existentes.add(clave)
        creados += 1
    return {"creados": creados, "omitidos": omitidos, "fecha": fecha.isoformat()}
