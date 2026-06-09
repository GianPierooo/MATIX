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

import logging
from datetime import date, datetime, timezone
from typing import Any
from zoneinfo import ZoneInfo

from ..comandos.recurrencia import ocurre_en, sesion_ocurre_en
from ..db import Postgrest
from . import creacion_proyecto

logger = logging.getLogger("matix.horario")

# `ocurre_en` se re-exporta desde aquí por compatibilidad (lo importan
# `asistencia_eventos` y los tests). El motor vive en `comandos/recurrencia`.
__all__ = ["ocurre_en", "sesion_ocurre_en"]

LIMA = ZoneInfo("America/Lima")

# Defaults si aún no hay fila de config_horario (el planner funciona igual).
_CFG_DEFAULT: dict[str, Any] = {
    "hora_despertar": 7,
    "hora_dormir": 23,
    "pico_inicio": 6,
    "pico_fin": 9,
    "buffer_min": 10,
    # Buffer de cierre: el día útil termina N minutos ANTES del ancla de dormir.
    # Antes el planificador apuraba cosas hasta las 23:00 si dormías a las 23:00.
    # Ahora resta este buffer para no proponer "hoy 22:30" como bloque de trabajo.
    "buffer_pre_sueno_min": 60,
    # Buffer de TRANSICIÓN tras un compromiso FUERA DE CASA (clase, evento con
    # ubicación): volver/reacomodarse antes de retomar trabajo de casa. Default
    # global; cada evento puede traer su override (`transicion_min`).
    "transicion_min": 60,
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
    buffer_pre_sueno_min: int = 0,
) -> list[dict[str, int]]:
    """Huecos reales del día dentro de [despertar, fin_util], donde
    `fin_util = dormir_min - buffer_pre_sueno_min` (no se planifica pegado al
    sueño). Resta lo fijo (con `buffer_min`). Si `desde_min` (replan desde
    ahora), recorta lo anterior. NUNCA pasa de `fin_util`. PURO."""
    # Tope útil: para no proponer "hoy 22:30" si duermes a las 23. El buffer
    # nunca consume todo el día (siempre quede al menos 30 min hábiles).
    fin_util = max(despertar_min + 30, dormir_min - max(0, buffer_pre_sueno_min))
    inicio = despertar_min if desde_min is None else max(despertar_min, desde_min)
    if inicio >= fin_util:
        return []
    ocupados = fusionar_ocupados(compromisos, buffer_min=buffer_min)
    libres: list[dict[str, int]] = []
    cursor = inicio
    for oi, of in ocupados:
        if of <= cursor:
            continue
        if oi > cursor:
            fin = min(oi, fin_util)
            if fin > cursor:
                libres.append({"ini": cursor, "fin": fin, "dur": fin - cursor})
        cursor = max(cursor, of)
        if cursor >= fin_util:
            break
    if cursor < fin_util:
        libres.append({"ini": cursor, "fin": fin_util, "dur": fin_util - cursor})
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


def items_backlog(
    tareas: list[dict[str, Any]],
    *,
    set_tarea_ids: set[str],
    dur_tarea_min: int,
    tope: int = 3,
) -> list[dict[str, Any]]:
    """BACKLOG VIVO (puro y testeable): tareas SIN fecha y SIN bloque que no
    están en el set ni completadas. Antes morían invisibles al plan; ahora se
    ofrecen como tarea ligera (no son trabajo profundo, no van al pico), con
    tope para no ahogar el día. No tocan tareas ya agendadas. PURO."""
    out: list[dict[str, Any]] = []
    for t in tareas:
        if len(out) >= tope:
            break
        if t.get("completada") or t.get("id") in set_tarea_ids:
            continue
        if t.get("bloque_inicio") or t.get("vence_en"):
            continue
        out.append({
            "titulo": t.get("titulo") or "Tarea",
            "tipo": "tarea",
            "dur": int(dur_tarea_min),
            # Prioridad/orden ALTOS = al final → solo entra si sobra espacio,
            # después del set, las de hoy y las skills.
            "prioridad": 9, "orden": 300,
            "tarea_id": t.get("id"),
            "backlog": True,
        })
    return out


def _norm(s: Any) -> str:
    """Normaliza un título para comparar sin tropezar con tildes/mayúsculas/
    espacios (p. ej. 'Calistenia' vs 'calistenia '). PURO."""
    t = str(s or "").strip().lower()
    tildes = str.maketrans("áéíóúüñ", "aeiouun")
    return t.translate(tildes)


def es_continuo_intercalado(modalidad: Any) -> bool:
    """`True` si el proyecto trabaja en modalidad CONTINUO INTERCALADO: sus
    tareas pelean por huecos profundos del día junto con las otras (lo que el
    planificador ya hace en `colocar()`), SIN slot fijo dedicado. Es la
    modalidad default de Matix: si la columna `proyectos.modalidad` viene NULL
    o vacía, también se considera continuo intercalado.
    Sirve para que el planificador, cuando vea otra modalidad en el futuro
    (`slot_fijo`), pueda ramificar SIN romper proyectos viejos. PURA."""
    if modalidad is None:
        return True
    m = str(modalidad).strip().lower()
    return m == "" or m == "continuo_intercalado"


def anclas_fijas(
    anclas: list[dict[str, Any]],
    *,
    iso_weekday: int,
    skills_norm: set[str] | None = None,
) -> list[dict[str, Any]]:
    """Anclas que rigen HOY como bloques FIJOS (inmovibles). EXCLUYE las que son
    una PRÁCTICA de skill: una práctica nunca es fija — se coloca tentativa, en
    tiempo ligero, y se puede mover. Solo clases y eventos (gym) son fijos; las
    anclas que NO son skill (rutinas que el usuario fijó a propósito) siguen
    fijas. Sacar la skill-ancla de la mañana además libera el pico para trabajo.
    PURO y testeable."""
    sk = skills_norm or set()
    out: list[dict[str, Any]] = []
    for a in anclas or []:
        if iso_weekday not in (a.get("dias") or [1, 2, 3, 4, 5, 6, 7]):
            continue
        titulo = a.get("titulo") or "Ancla"
        if _norm(titulo) in sk:
            continue  # es una skill → tentativa, no fija (la coloca `colocar`)
        ini = hhmm_a_min(a.get("inicio") or "")
        fin = hhmm_a_min(a.get("fin") or "")
        if ini is None or fin is None or fin <= ini:
            continue
        out.append({"ini_min": ini, "fin_min": fin, "tipo": "ancla",
                    "titulo": titulo})
    return out


def bloques_transicion(
    fijos: list[dict[str, Any]], *, transicion_default_min: int
) -> list[dict[str, Any]]:
    """Tras cada compromiso FUERA DE CASA (clase de uni o evento con `ubicacion`)
    reserva un bloque de TRANSICIÓN —volver a casa / reacomodarse— donde el
    planificador NO coloca trabajo de casa. Usa el override del evento
    (`transicion_min`) si lo trae; si no, el default global. 0 (o negativo) =
    sin transición para ese compromiso. SOLO después (el `buffer_min` corto ya
    pad-ea ambos lados). PURO y testeable.

    Espera que cada `fijo` traiga `fuera_casa: bool` y opcionalmente
    `transicion_min` (override). No genera transición tras una transición."""
    out: list[dict[str, Any]] = []
    for c in fijos:
        if not c.get("fuera_casa"):
            continue
        override = c.get("transicion_min")
        try:
            dur = int(transicion_default_min if override is None else override)
        except (TypeError, ValueError):
            dur = int(transicion_default_min)
        if dur <= 0:
            continue
        fin = c.get("fin_min")
        if fin is None:
            continue
        out.append({"ini_min": int(fin), "fin_min": int(fin) + dur,
                    "tipo": "transicion", "titulo": "Transición"})
    return out


def accion_siguiente_proyecto(
    proyecto: dict[str, Any],
    candidatos: list[dict[str, Any]],
    *,
    dur_trabajo_min: int,
) -> dict[str, Any]:
    """La ACCIÓN SIGUIENTE de un proyecto de trabajo para el plan, derivada de su
    descomposición por horizontes: el primer nodo fino DESBLOQUEADO (`candidatos`,
    ya filtrados por `planificador_diario.candidatos_proyecto`). Si el proyecto no
    tiene árbol o no le queda nodo abierto, sintetiza una acción de PLANIFICACIÓN
    («Definir el siguiente paso de X») — así NINGÚN proyecto activo queda sin
    acción siguiente (mata el bug «0%, sin acción»). Es trabajo profundo (pelea
    por el pico), pero con `orden` alto: nunca desplaza al set comprometido. PURO."""
    pid = proyecto.get("id")
    nombre = proyecto.get("nombre") or "tu proyecto"
    prio = proyecto.get("prioridad") or 9
    base = {
        "tipo": "trabajo", "dur": int(dur_trabajo_min),
        "prioridad": prio, "orden": 120,
        "proyecto_id": pid, "proyecto": nombre, "auto_siguiente": True,
    }
    if candidatos:
        n = candidatos[0]
        return {**base, "titulo": n.get("titulo") or "Siguiente paso",
                "nodo_id": n.get("id")}
    return {**base, "titulo": f"Definir el siguiente paso de {nombre}",
            "auto_planificacion": True}


def etiqueta_duracion(mins: int) -> str:
    """Duración legible en español: '45 min', '1 h', '1 h 30 min'. PURO."""
    mins = max(0, int(mins))
    h, m = divmod(mins, 60)
    if h and m:
        return f"{h} h {m} min"
    if h:
        return f"{h} h"
    return f"{m} min"


def huecos_libres(
    bloques: list[dict[str, Any]], *, inicio_min: int, fin_min: int
) -> list[dict[str, int]]:
    """Huecos REALES que quedan libres tras colocar TODO (fijos + transiciones +
    tentativos): el tiempo dentro de [inicio, fin] no cubierto por ningún bloque.
    Sin buffer (es el tiempo verdaderamente libre que el usuario ve). PURO."""
    if inicio_min >= fin_min:
        return []
    ocupados = fusionar_ocupados(bloques, buffer_min=0)
    libres: list[dict[str, int]] = []
    cursor = inicio_min
    for oi, of in ocupados:
        if of <= cursor:
            continue
        if oi > cursor:
            fin = min(oi, fin_min)
            if fin > cursor:
                libres.append({"ini": cursor, "fin": fin, "dur": fin - cursor})
        cursor = max(cursor, of)
        if cursor >= fin_min:
            break
    if cursor < fin_min:
        libres.append({"ini": cursor, "fin": fin_min, "dur": fin_min - cursor})
    return [v for v in libres if v["dur"] > 0]


def huecos_con_sugerencia(
    huecos: list[dict[str, int]], pool: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """Apartado de HUECOS LIBRES: para cada hueco, su rango + duración legible y
    UNA sugerencia DOSIFICADA que de verdad QUEPA (la de mayor valor del pool que
    entre en la ventana), o `None` si no hay nada pendiente que entre. Una cosa
    por hueco (no avalancha) y no repite la misma sugerencia en dos huecos. El
    `pool` ya viene ordenado por prioridad (lo que no entró, en orden). PURO."""
    usados: set[int] = set()
    out: list[dict[str, Any]] = []
    for h in huecos:
        dur = int(h["dur"])
        elegida = None
        for idx, s in enumerate(pool):
            if idx in usados:
                continue
            if int(s.get("dur_min") or 0) <= dur:
                elegida = s
                usados.add(idx)
                break
        out.append({
            "inicio": min_a_hhmm(h["ini"]), "fin": min_a_hhmm(h["fin"]),
            "dur_min": dur, "etiqueta": etiqueta_duracion(dur),
            "sugerencia": elegida,
        })
    return out


def pool_sugerencias(fuera: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """De lo que NO entró hoy arma un pool de sugerencias ofrecibles en los huecos
    libres (práctica de skill o tarea de proyecto corto), cada una con su duración
    para casar por tamaño de hueco. La app dosifica: una por hueco, sin rellenar.
    PURO."""
    pool: list[dict[str, Any]] = []
    for f in fuera:
        pool.append({
            "titulo": f.get("titulo") or "",
            "tipo": f.get("tipo") or "",
            "dur_min": int(f.get("dur") or 30),
            "proyecto": f.get("proyecto"),
            "skill": f.get("skill"),
            "proyecto_id": f.get("proyecto_id"),
            "nodo_id": f.get("nodo_id"),
            "tarea_id": f.get("tarea_id"),
            "set_item_id": f.get("set_item_id"),
        })
    return pool


# ── Helpers de recurrencia / fechas (puros) ──────────────────────────────────

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
    db: Postgrest, *, fecha: date, anclas: list[dict[str, Any]],
    skills_norm: set[str] | None = None, transicion_default_min: int = 0,
) -> list[dict[str, Any]]:
    """Clases de uni (sesiones_clase) + recurrentes/sueltos (eventos) + anclas,
    como rangos en minutos. NO duplica: lee de donde ya viven. Las anclas que son
    una práctica de skill NO entran acá (son tentativas, no fijas): se excluyen
    con `skills_norm`.

    Tras cada compromiso FUERA DE CASA (clase, o evento con `ubicacion`) anexa un
    bloque de TRANSICIÓN (`transicion_default_min`, o el override del evento) para
    no colocar trabajo de casa pegado a la salida."""
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
    for s in sesiones:
        # Mismo motor que los eventos recurrentes: "¿esta clase cae hoy?".
        dia = s.get("dia_semana")
        if dia is None or not sesion_ocurre_en(dia, fecha):
            continue
        ini = hhmm_a_min(s.get("hora_inicio") or "")
        fin = hhmm_a_min(s.get("hora_fin") or "")
        if ini is None or fin is None:
            continue
        # Una clase es FUERA DE CASA (la uni): merece transición de vuelta.
        fijos.append({"ini_min": ini, "fin_min": fin, "tipo": "clase",
                      "titulo": cursos.get(s.get("curso_id"), "Clase"),
                      "fuera_casa": True})

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
        # FUERA DE CASA si el evento tiene ubicación (gym, cita, etc.): se reserva
        # transición de vuelta. El evento puede traer su propio `transicion_min`.
        fuera = bool((e.get("ubicacion") or "").strip())
        fijos.append({"ini_min": ini, "fin_min": fin, "tipo": "evento",
                      "titulo": e.get("titulo") or "Evento",
                      "fuera_casa": fuera, "transicion_min": e.get("transicion_min")})

    # Anclas editables: solo las que NO son práctica de skill (esas son
    # tentativas). La lógica vive en `anclas_fijas` para testearla sin BD.
    fijos.extend(anclas_fijas(
        anclas, iso_weekday=fecha.isoweekday(), skills_norm=skills_norm,
    ))

    # Transición tras lo que es fuera de casa (lógica pura, testeable sin BD).
    if transicion_default_min:
        fijos.extend(bloques_transicion(
            fijos, transicion_default_min=transicion_default_min,
        ))

    fijos.sort(key=lambda c: c["ini_min"])
    return fijos


async def _items_a_colocar(
    db: Postgrest, *, fecha: date, cfg: dict[str, Any], solo_pendientes: bool,
    titulos_fijos: set[str] | None = None,
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

    # Ids de proyectos de TRABAJO (no skills): sus tareas son trabajo PROFUNDO
    # (van al pico), no slots chicos. Además filtramos por MODALIDAD: solo
    # entran los `continuo_intercalado` (o sin modalidad, que es el default
    # histórico de Matix). Los que en el futuro lleven `slot_fijo` se manejarán
    # como ancla; los `esporadico` no obligan al planificador a colocarlos.
    ids_trabajo = {
        p["id"] for p in proyectos
        if p.get("estado") == "activo"
        and not creacion_proyecto.es_skill(p)
        and es_continuo_intercalado(p.get("modalidad"))
    }
    nombre_proy = {p["id"]: p.get("nombre") for p in proyectos}

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
        pid = t.get("proyecto_id")
        if pid in ids_trabajo:
            # Tarea de un proyecto de trabajo → bloque de trabajo profundo (pico).
            items.append({
                "titulo": t.get("titulo") or "Tarea", "tipo": "trabajo",
                "dur": int(cfg["dur_trabajo_min"]),
                "prioridad": prio.get(pid, 9), "orden": 50,
                "proyecto_id": pid, "tarea_id": t.get("id"),
                "proyecto": nombre_proy.get(pid),
            })
        else:
            items.append({
                "titulo": t.get("titulo") or "Tarea", "tipo": "tarea",
                "dur": int(cfg["dur_tarea_min"]), "prioridad": 5, "orden": 100,
                "tarea_id": t.get("id"),
            })

    # BACKLOG VIVO: tareas SIN fecha y SIN bloque entran como tarea ligera (no
    # son trabajo profundo: no van al pico), con tope para no ahogar el día. La
    # lógica vive en `items_backlog` para testearla sin BD.
    items.extend(items_backlog(
        tareas, set_tarea_ids=set_tarea_ids,
        dur_tarea_min=int(cfg["dur_tarea_min"]),
    ))

    # NINGÚN proyecto activo sin acción siguiente (#2): si un proyecto de trabajo
    # no quedó representado por el set ni por una tarea de hoy, le derivo su
    # siguiente paso del árbol (primer nodo fino abierto); si no tiene árbol/nodo,
    # sintetizo «Definir el siguiente paso de X». Así nunca vuelve el «0%, sin
    # acción». Determinista (selección por cálculo, sin LLM).
    from . import planificador_diario  # lazy: evita ciclo de import
    proy_por_id = {p["id"]: p for p in proyectos}
    proyectos_con_item = {
        i.get("proyecto_id") for i in items
        if i.get("tipo") == "trabajo" and i.get("proyecto_id")
    }
    for pid in ids_trabajo:
        if pid in proyectos_con_item:
            continue
        try:
            nodos = await db.list(
                "arbol_nodos", filters={"proyecto_id": pid}, order="orden.asc"
            )
        except Exception:  # noqa: BLE001
            nodos = []
        candidatos = planificador_diario.candidatos_proyecto(nodos)
        items.append(accion_siguiente_proyecto(
            proy_por_id.get(pid, {"id": pid, "nombre": nombre_proy.get(pid)}),
            candidatos, dur_trabajo_min=int(cfg["dur_trabajo_min"]),
        ))

    # Skills activas: slot chico opcional cada una (lo más ligero, va al final).
    # Si la skill YA tiene su rutina como compromiso fijo del día (p. ej.
    # Calistenia a las 07:00), su práctica ocurre AHÍ: no agendamos un segundo
    # bloque tentativo duplicado.
    fijos_norm = titulos_fijos or set()
    skills = creacion_proyecto.solo_skills(
        [p for p in proyectos if p.get("estado") == "activo"]
    )
    for sk in skills:
        if _norm(sk["nombre"]) in fijos_norm:
            continue
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

    # Ancla de despertar SOLO-HOY (botón "Me acabo de levantar"): si hay un
    # registro para esta fecha, manda sobre la rutina estándar (que no se toca).
    override = await despertar_override_min(db, fecha)
    despertar = override if override is not None else int(cfg["hora_despertar"]) * 60
    dormir = int(cfg["hora_dormir"]) * 60
    buffer_min = int(cfg["buffer_min"])
    pico_ini = int(cfg["pico_inicio"]) * 60
    pico_fin = int(cfg["pico_fin"]) * 60

    # Nombres de skills ACTIVAS (normalizados): una ancla que coincide con una
    # skill es una práctica → tentativa, no fija. La sacamos de los compromisos
    # fijos para que el pico quede libre para trabajo y la práctica se mueva.
    try:
        _proys_activos = await db.list("proyectos", filters={"estado": "activo"})
    except Exception:  # noqa: BLE001
        _proys_activos = []
    skills_norm = {_norm(s["nombre"]) for s in creacion_proyecto.solo_skills(_proys_activos)}

    fijos = await _compromisos_fijos(
        db, fecha=fecha, anclas=cfg.get("anclas") or [], skills_norm=skills_norm,
        transicion_default_min=int(cfg.get("transicion_min", 0) or 0),
    )
    desde_min = (local.hour * 60 + local.minute) if desde_ahora else None
    ventanas = ventanas_libres(
        fijos, despertar_min=despertar, dormir_min=dormir,
        buffer_min=buffer_min, desde_min=desde_min,
        buffer_pre_sueno_min=int(cfg.get("buffer_pre_sueno_min", 0) or 0),
    )

    # Títulos de los compromisos fijos de hoy (normalizados) → una skill cuya
    # rutina ya cae en un fijo del día no se duplica como bloque tentativo.
    titulos_fijos = {_norm(c["titulo"]) for c in fijos}
    items = await _items_a_colocar(
        db, fecha=fecha, cfg=cfg, solo_pendientes=desde_ahora,
        titulos_fijos=titulos_fijos,
    )
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

    # Apartado de HUECOS LIBRES (#3): el tiempo que de verdad queda libre tras
    # colocar TODO (fijos + transiciones + tentativos), con UNA sugerencia que
    # quepa por hueco (motor determinista: el pool es lo que no entró, en orden
    # de prioridad). Instantáneo y sin tokens.
    fin_util = max(despertar + 30, dormir - int(cfg.get("buffer_pre_sueno_min", 0) or 0))
    inicio_huecos = despertar if desde_min is None else max(despertar, desde_min)
    ocupado_final = (
        [{"ini_min": c["ini_min"], "fin_min": c["fin_min"]} for c in fijos]
        + [{"ini_min": b["ini_min"], "fin_min": b["fin_min"]} for b in colocado["bloques"]]
    )
    pool = pool_sugerencias(colocado["fuera"])
    huecos = huecos_con_sugerencia(
        huecos_libres(ocupado_final, inicio_min=inicio_huecos, fin_min=fin_util),
        pool,
    )

    return {
        "fecha": fecha.isoformat(),
        "despierta": min_a_hhmm(despertar),
        "duerme": min_a_hhmm(dormir),
        "desde": min_a_hhmm(desde_min) if desde_min is not None else None,
        "bloques": bloques,
        "fuera": fuera,
        # Pool ofrecible en los huecos libres (la app dosifica: una por hueco).
        "sugerencias": pool,
        # Apartado legible de huecos libres + su sugerencia dosificada (una/hueco).
        "huecos": huecos,
    }


# ── Ancla de despertar POR DÍA (botón "Me acabo de levantar") ────────────────

async def despertar_override_min(db: Postgrest, fecha) -> int | None:
    """Minutos desde medianoche en que el usuario despertó HOY (registro
    por-día), o None si no marcó. NO toca la rutina estándar. Best-effort."""
    try:
        filas = await db.list(
            "despertar_dia", filters={"fecha": fecha.isoformat()}, limit=1
        )
    except Exception:  # noqa: BLE001
        return None
    if not filas:
        return None
    m = filas[0].get("minutos")
    return int(m) if m is not None else None


async def marcar_despertar(
    db: Postgrest, *, ahora: datetime | None = None
) -> dict[str, Any]:
    """Registra que el usuario despertó AHORA (ancla solo-hoy) y devuelve el
    plan del día recalculado desde esa hora — todo determinista, sin LLM.
    Reusa `plan_de_hoy_data(desde_ahora=True)` para que las cosas de hoy
    aparezcan al instante."""
    ahora = ahora or datetime.now(timezone.utc)
    local = ahora.astimezone(LIMA)
    fecha = local.date()
    minutos = local.hour * 60 + local.minute
    # Upsert por fecha (una marca por día; re-marcar actualiza la hora).
    try:
        filas = await db.list(
            "despertar_dia", filters={"fecha": fecha.isoformat()}, limit=1
        )
        if filas:
            await db.update("despertar_dia", filas[0]["fecha"], {"minutos": minutos})
        else:
            await db.insert(
                "despertar_dia", {"fecha": fecha.isoformat(), "minutos": minutos}
            )
    except Exception:  # noqa: BLE001
        logger.exception("marcar_despertar: no pude guardar el ancla de hoy")
    # Materializa el set del día (determinista) para que aparezca al instante.
    try:
        from . import planificador_diario

        await planificador_diario.construir_set(db, ahora=ahora)
    except Exception:  # noqa: BLE001
        logger.exception("marcar_despertar: no pude construir el set del día")
    plan = await plan_de_hoy_data(db, ahora=ahora, desde_ahora=True)
    return {"despierta_hoy": min_a_hhmm(minutos), "plan": plan}


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
        # Completar por el COMANDO canónico (D5): mismo estado que completar por
        # checkbox o por la tool de la IA — repetición + sync de árbol/set
        # incluidos. Antes este camino del bloque NO creaba la siguiente
        # instancia repetida ni sincronizaba el nodo del árbol.
        from ..comandos import registro

        await registro.ejecutar(
            db, "completar_tarea", {"tarea_id": tarea_id}, origen="bloque"
        )
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


def _bloque_inicio_es_hoy(tarea: dict[str, Any], fecha: date) -> bool:
    bi = _parse_dt(tarea.get("bloque_inicio"))
    return bi is not None and bi.astimezone(LIMA).date() == fecha


async def agendar_plan(
    db: Postgrest,
    *,
    bloques: list[dict[str, Any]] | None = None,
    ahora: datetime | None = None,
) -> dict[str, Any]:
    """Agenda los bloques tentativos del plan como TAREAS del hub — el ÚNICO
    camino canónico de "agregar al día". NUNCA crea eventos pelados (los eventos
    solo nacen por la ruta explícita de evento fijo: clase, gym).

    Reusa el modelo Tarea↔bloque:
    - Si el bloque ya viene de una tarea (`tarea_id`) → le engancha su horario
      (`bloque_inicio/fin`, vence hoy).
    - Si viene de un item del set (`set_item_id`) → lo promueve a Tarea
      (reusa `planificador_diario.aceptar_items`) y la engancha.
    - Si no tiene tarea (skill, sugerencia sintetizada, nodo) → crea una Tarea
      nueva con su bloque (y la enlaza al nodo del árbol si lo trae).

    Así TODO lo que agregas aparece en Tareas Y en Tu día. Idempotente: una tarea
    ya enganchada se re-actualiza; las nuevas se dedupean por título + bloque de
    hoy. Si la app pasa `bloques` (con sus ediciones), se usan esos."""
    ahora = ahora or datetime.now(timezone.utc)
    local = ahora.astimezone(LIMA)
    fecha = local.date()
    if bloques is None:
        data = await plan_de_hoy_data(db, ahora=ahora)
        bloques = [b for b in data["bloques"] if b.get("tentativo")]

    from . import planificador_diario

    try:
        tareas = await db.list(
            "tareas",
            raw_filters={"eliminado_en": "is.null", "completada": "is.false"},
            limit=500,
        )
    except Exception:  # noqa: BLE001
        tareas = []
    titulos_hoy = {_norm(t.get("titulo")) for t in tareas if _bloque_inicio_es_hoy(t, fecha)}

    agendadas, omitidas = 0, 0
    for b in bloques:
        titulo = (b.get("titulo") or "").strip()
        inicio = (b.get("inicio") or "").strip()
        if not titulo or not inicio:
            continue
        fin = (b.get("fin") or "").strip() or min_a_hhmm((hhmm_a_min(inicio) or 0) + 30)
        ini_iso = _hhmm_a_utc_iso(fecha, inicio)
        fin_iso = _hhmm_a_utc_iso(fecha, fin)

        tid = b.get("tarea_id")
        # Item del set 'propuesto' → promover a tarea (reusa el flujo del set).
        if not tid and b.get("set_item_id"):
            try:
                prom = await planificador_diario.aceptar_items(
                    db, item_ids=[b["set_item_id"]], ahora=ahora
                )
                if prom:
                    tid = prom[0].get("tarea_id")
            except Exception:  # noqa: BLE001
                logger.exception("agendar: no pude promover el item del set")

        if tid:
            await db.update(
                "tareas", tid,
                {"bloque_inicio": ini_iso, "bloque_fin": fin_iso, "vence_en": fin_iso},
            )
            agendadas += 1
            continue

        # Sin tarea (skill / sugerencia sintetizada / nodo): crear una Tarea.
        if _norm(titulo) in titulos_hoy:
            omitidas += 1
            continue
        nueva = await db.insert("tareas", {
            "titulo": titulo,
            "proyecto_id": b.get("proyecto_id"),
            "bloque_inicio": ini_iso,
            "bloque_fin": fin_iso,
            "vence_en": fin_iso,
            "nudges_silenciada": True,
        })
        if b.get("nodo_id"):
            try:
                await db.update(
                    "arbol_nodos", b["nodo_id"],
                    {"tarea_id": nueva["id"], "estado": "en_curso"},
                )
            except Exception:  # noqa: BLE001
                logger.exception("agendar: no pude enlazar el nodo")
        titulos_hoy.add(_norm(titulo))
        agendadas += 1

    return {"agendadas": agendadas, "omitidas": omitidas, "fecha": fecha.isoformat()}
