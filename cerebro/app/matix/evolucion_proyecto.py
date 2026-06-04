"""Motor de evolución de proyectos + seguimiento.

Con el tiempo, Matix mejora cada proyecto SIN perder coherencia con el todo
(pasado, presente y futuro): revisión holística (no duplica lo hecho ni
contradice el plan), generación progresiva (elabora la próxima fase gruesa al
acercarse), check-in semanal, detección de estancamiento con re-scope honesto, y
adaptación al ritmo (sin castigar). Más notificaciones (porqué de la mañana,
check-in, celebración de hitos, aviso de estancamiento) sobre FCM + el motor
diario.

NO toca el cálculo de horario/ventanas (eso es otro paso). Reusa el árbol
(Paso 2), el % de avance, el perfil (porqué/criterios), el scheduler y FCM.

La parte PURA está separada y se testea sin BD.

ANTI-PATRONES que este motor evita EXPLÍCITAMENTE (y dónde):
- No duplicar tareas: `filtrar_duplicados` + `contexto_holistico` (nodos_existentes)
  → el review nunca propone algo ya hecho o ya en la lista.
- No apilar cuando va atrasado: `planificador_diario.ajustar_tamano_set` REDUCE
  el set según el ritmo real; el review re-prioriza/re-escopa, no suma.
- No bombardear (escalar, no fastidiar): cadencia + anti-fatiga del planificador;
  hitos y check-in con dedup (un solo aviso).
- No fastidiar hobbies: las skills se excluyen del set comprometido y del aviso
  de estancamiento (`creacion_proyecto.solo_proyectos`); su dosis es suave.
- Respetar el silencio 22:00–08:00 (America/Lima): `_en_ventana` /
  `recordatorios.permitido_ahora` en cada tick que notifica.
- Anti-abandono: `estancado` + `sugerir_reescopeo` agarran el estancamiento
  temprano y proponen achicar el paso (o parquear sin culpa), no dejar morir.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo

from ..db import Postgrest
from . import avance as avance_mod
from . import creacion_proyecto
from .planificador_diario import LIMA, _push, _tokens, candidatos_proyecto

logger = logging.getLogger("matix.evolucion")

# Días sin actividad para considerar un proyecto ESTANCADO.
DIAS_ESTANCAMIENTO = 5
# No repetir el aviso de estancamiento más seguido que esto.
DIAS_ENTRE_AVISOS_ESTANCAMIENTO = 4
# Margen para clasificar el ritmo (% sobre/bajo lo esperado).
_MARGEN_RITMO = 15


# ════════════════════════════════════════════════════════════════════════════
# LÓGICA PURA (testeable sin BD)
# ════════════════════════════════════════════════════════════════════════════

def filtrar_duplicados(candidatas: list[str], existentes: list[str]) -> list[str]:
    """Quita de `candidatas` lo que ya existe en el árbol (hecho o pendiente):
    coherencia, no duplicar. Compara normalizado (una contiene a la otra). PURO.
    """
    norm_exist = [_norm(e) for e in existentes if e and e.strip()]
    out: list[str] = []
    vistas: list[str] = []
    for c in candidatas:
        n = _norm(c)
        if not n:
            continue
        if any(n == e or n in e or e in n for e in norm_exist):
            continue
        if any(n == v or n in v or v in n for v in vistas):
            continue  # tampoco duplicar entre las nuevas
        vistas.append(n)
        out.append(c)
    return out


def fase_a_elaborar(nodos: list[dict[str, Any]]) -> dict[str, Any] | None:
    """La próxima fase GRUESA a elaborar (generación progresiva): la primera
    fase raíz NO terminada; si es gruesa (sin desglosar), es la que toca
    elaborar al acercarse. Si la primera no-terminada es fina, todavía se está
    trabajando esa: None (no adelantar fases lejanas). PURO."""
    raices = sorted(
        [n for n in nodos if not n.get("parent_id")], key=lambda x: x.get("orden", 0)
    )
    hijos = {n.get("id") for n in nodos if n.get("parent_id")}
    for r in raices:
        if r.get("estado") == "hecho":
            continue
        # primera fase no terminada
        es_hoja = r.get("id") not in hijos
        if r.get("granularidad") == "grueso" and es_hoja:
            return r
        return None  # la actual es fina y sigue en curso → no adelantar
    return None


def estancado(
    ultima_actividad_iso: Any, *, ahora: datetime, dias_umbral: int = DIAS_ESTANCAMIENTO
) -> dict[str, Any]:
    """¿El proyecto está estancado? (días sin actividad ≥ umbral). PURO."""
    ult = _parse(ultima_actividad_iso)
    if ult is None:
        return {"estancado": False, "dias": 0}
    dias = (ahora - ult).days
    return {"estancado": dias >= dias_umbral, "dias": dias}


def evaluar_ritmo(
    avance_pct: int, dias_transcurridos: int, dias_totales: int
) -> dict[str, Any]:
    """Compara el avance real con el esperado por el tiempo transcurrido y
    recomienda SIN castigar: adelantado → estirar; atrasado → re-priorizar/
    re-scopear (no apilar tareas); al día → seguir. PURO."""
    if dias_totales <= 0:
        return {"ritmo": "al_dia", "esperado_pct": 0, "recomendacion": "Sigue así."}
    esperado = max(0, min(100, round(dias_transcurridos / dias_totales * 100)))
    if avance_pct >= esperado + _MARGEN_RITMO:
        rec = "Vas adelantado: si quieres, sumamos un estiramiento opcional."
        ritmo = "adelantado"
    elif avance_pct <= esperado - _MARGEN_RITMO:
        rec = ("Vas algo atrasado: NO te apilo tareas. Re-priorizamos lo esencial "
               "o ajustamos el alcance/plazo para que sea realista.")
        ritmo = "atrasado"
    else:
        rec = "Vas al día. Mantén el ritmo."
        ritmo = "al_dia"
    return {"ritmo": ritmo, "esperado_pct": esperado, "recomendacion": rec}


# ── Copy de notificaciones (puro) ───────────────────────────────────────────

def texto_porque_morning(nombre: str, porque: str) -> tuple[str, str]:
    return (
        "🌅 Tu porqué de hoy",
        f"{nombre}: lo haces porque {porque.rstrip('.')}. Un paso hoy te acerca. "
        "Toca para ver tu set.",
    )


def linea_checkin_proyecto(
    *, nombre: str, pct: int | None, estancado_dias: int, siguiente: str | None
) -> str:
    """Una línea HONESTA por proyecto para el check-in semanal: cuánto va (%),
    si está trabado, y qué sigue. Sin maquillar. PURO."""
    estado = f"{pct}%" if pct is not None else "sin plan"
    if estancado_dias and estancado_dias >= DIAS_ESTANCAMIENTO:
        estado += f", trabado {estancado_dias}d"
    sig = f" → sigue: {siguiente}" if siguiente else ""
    return f"{nombre} ({estado}){sig}"


def texto_checkin(resumenes: list[str] | None = None) -> tuple[str, str]:
    """Check-in semanal. Si se pasan resúmenes por proyecto, el cuerpo es la foto
    honesta de la semana; si no, el genérico. PURO."""
    if resumenes:
        cuerpo = " · ".join(resumenes[:3])
        if len(resumenes) > 3:
            cuerpo += f" · +{len(resumenes) - 3} más"
        return ("📈 Check-in semanal", f"{cuerpo}. Toca para revisarlo conmigo.")
    return (
        "📈 Check-in semanal",
        "Revisemos cómo van tus proyectos: qué avanzó, qué se estancó y qué "
        "reajustamos. Toca para verlo conmigo.",
    )


def texto_hito(nombre: str, fase: str) -> tuple[str, str]:
    return (
        "🎉 ¡Hito cumplido!",
        f"Cerraste «{fase}» en {nombre}. Bien ahí, en serio. Vamos por lo que sigue.",
    )


# Umbrales de % que se celebran (refuerzo positivo, sin spam: cada uno UNA vez).
_UMBRALES_PCT = (25, 50, 75, 100)


def umbrales_cruzados(pct: int | None) -> list[int]:
    """Umbrales de avance (25/50/75/100) ya alcanzados a este %. PURO."""
    if pct is None:
        return []
    return [u for u in _UMBRALES_PCT if pct >= u]


def texto_hito_pct(nombre: str, umbral: int) -> tuple[str, str]:
    """Celebra cruzar un umbral de avance. PURO."""
    if umbral >= 100:
        return ("🏁 ¡Lo cerraste!", f"{nombre} al 100%. Lo terminaste, en serio. Disfruta esto.")
    return ("🎉 Hito de avance", f"{nombre} cruzó el {umbral}%. Vas bien, un paso a la vez suma.")


def sugerir_reescopeo(nodo_titulo: str | None) -> str | None:
    """Re-scope HONESTO ante el estancamiento (guardrail anti-abandono): propone
    ACHICAR el siguiente paso a un trozo mínimo, en vez de dejar morir el
    proyecto en silencio. PURO."""
    if not nodo_titulo:
        return None
    return (
        f"Si «{nodo_titulo}» se siente grande, lo achicamos a un primer paso de "
        "10-15 min. Mejor un trozo chico hoy que cero. O lo parqueamos sin culpa."
    )


def texto_estancamiento(nombre: str, dias: int) -> tuple[str, str]:
    return (
        "🌱 ¿Retomamos esto?",
        f"{nombre} lleva {dias} días sin avance. ¿Sigue activo, lo reajustamos o "
        "lo parqueamos un rato? Sin culpa: tú decides. Toca para hablarlo.",
    )


# ════════════════════════════════════════════════════════════════════════════
# Ticks del scheduler (best-effort; nunca lanzan)
# ════════════════════════════════════════════════════════════════════════════

def _en_ventana(local: datetime, db_cfg: dict | None) -> bool:
    """Respeta silencio + ventana de disponibilidad (reusa config_nudges)."""
    from . import recordatorios
    if not db_cfg:
        # Sin config: solo evita la franja de silencio por defecto 22-08.
        return not (local.hour >= 22 or local.hour < 8)
    return recordatorios.permitido_ahora(local, db_cfg)


async def _cfg_nudges(db: Postgrest) -> dict | None:
    filas = await db.list("config_nudges", limit=1)
    return filas[0] if filas else None


async def _ya(db: Postgrest, tipo: str, fecha_iso: str) -> bool:
    filas = await db.list(
        "planificacion_enviados", filters={"tipo": tipo, "fecha": fecha_iso}, limit=1
    )
    return bool(filas)


async def _ya_tipo(db: Postgrest, tipo: str) -> bool:
    """¿Ya se envió alguna vez algo de este `tipo` (cualquier fecha)? Para hitos
    de % que se celebran una sola vez en la vida del proyecto."""
    filas = await db.list("planificacion_enviados", filters={"tipo": tipo}, limit=1)
    return bool(filas)


async def revisar_checkin(db: Postgrest, *, ahora: datetime | None = None) -> dict:
    """Check-in semanal (un solo push, no por proyecto, anti-spam): el lunes,
    dentro de ventana, una vez por semana ISO."""
    ahora = ahora or datetime.now(timezone.utc)
    local = ahora.astimezone(LIMA)
    if local.isoweekday() != 1:  # lunes
        return {"checkin": 0}
    cfg = await _cfg_nudges(db)
    if not _en_ventana(local, cfg):
        return {"checkin": 0, "fuera_de_ventana": True}
    # El check-in semanal es sobre los proyectos de TRABAJO; si solo hay skills
    # activas, no hay nada que revisar con esa lente.
    activos_trabajo = creacion_proyecto.solo_proyectos(
        await db.list("proyectos", filters={"estado": "activo"})
    )
    if not activos_trabajo:
        return {"checkin": 0, "sin_activos": True}
    semana = (local.date() - timedelta(days=local.isoweekday() - 1)).isoformat()
    if await _ya(db, "checkin", semana):
        return {"checkin": 0, "ya": True}
    tokens = await _tokens(db)
    if not tokens:
        return {"checkin": 0, "sin_tokens": True}
    # Resumen HONESTO por proyecto de trabajo activo: % real, si está trabado y
    # qué sigue. Una sola notificación semanal (anti-spam); el detalle se
    # conversa al tocarla (review holístico en el modelo fuerte).
    activos_trabajo.sort(key=lambda p: p.get("prioridad") or 99)
    resumenes: list[str] = []
    for p in activos_trabajo:
        nodos = await db.list("arbol_nodos", filters={"proyecto_id": p["id"]}, order="orden.asc")
        pct = avance_mod.porcentaje(nodos)
        est = estancado(p.get("ultima_actividad_en"), ahora=ahora)
        cands = candidatos_proyecto(nodos)
        siguiente = cands[0].get("titulo") if cands else None
        resumenes.append(linea_checkin_proyecto(
            nombre=p["nombre"], pct=pct,
            estancado_dias=est["dias"] if est["estancado"] else 0,
            siguiente=siguiente,
        ))
    titulo, cuerpo = texto_checkin(resumenes)
    try:
        if await _push(db, tokens, titulo=titulo, cuerpo=cuerpo, payload="checkin"):
            await db.insert("planificacion_enviados", {"tipo": "checkin", "fecha": semana})
            return {"checkin": 1}
    except RuntimeError:
        return {"checkin": 0, "error": "fcm_no_config"}
    return {"checkin": 0}


async def revisar_hitos(db: Postgrest, *, ahora: datetime | None = None) -> dict:
    """Celebra fases raíz recién completadas (100% y con hijos) que aún no se
    celebraron. Marca celebrado_en para no repetir."""
    ahora = ahora or datetime.now(timezone.utc)
    local = ahora.astimezone(LIMA)
    cfg = await _cfg_nudges(db)
    if not _en_ventana(local, cfg):
        return {"hitos": 0, "fuera_de_ventana": True}
    activos = await db.list("proyectos", filters={"estado": "activo"})
    enviados = 0
    for p in activos:
        nodos = await db.list("arbol_nodos", filters={"proyecto_id": p["id"]}, order="orden.asc")
        por_id = {n["id"]: n for n in nodos}
        for fase in avance_mod.desglose_por_fase(nodos):
            nodo = por_id.get(fase.get("id"))
            if not nodo or nodo.get("celebrado_en"):
                continue
            if fase.get("porcentaje") == 100 and fase.get("tiene_hijos"):
                tokens = await _tokens(db)
                if not tokens:
                    return {"hitos": enviados, "sin_tokens": True}
                titulo, cuerpo = texto_hito(p["nombre"], fase["fase"])
                try:
                    if await _push(db, tokens, titulo=titulo, cuerpo=cuerpo, payload=f"proyecto:{p['id']}"):
                        await db.update("arbol_nodos", nodo["id"], {"celebrado_en": ahora.isoformat()})
                        enviados += 1
                except RuntimeError:
                    return {"hitos": enviados, "error": "fcm_no_config"}
    return {"hitos": enviados}


async def revisar_hitos_pct(db: Postgrest, *, ahora: datetime | None = None) -> dict:
    """Celebra cruzar umbrales de avance (25/50/75/100) por proyecto/skill activo.
    Refuerzo positivo, con dedup (cada umbral UNA vez en la vida del proyecto) y
    respetando el silencio. INCLUYE skills: celebrar no es insistir."""
    ahora = ahora or datetime.now(timezone.utc)
    local = ahora.astimezone(LIMA)
    cfg = await _cfg_nudges(db)
    # ANTI-PATRÓN (silencio 22-08) + (no bombardear): solo en ventana y una vez
    # por umbral.
    if not _en_ventana(local, cfg):
        return {"hitos_pct": 0, "fuera_de_ventana": True}
    activos = await db.list("proyectos", filters={"estado": "activo"})
    enviados = 0
    for p in activos:
        nodos = await db.list("arbol_nodos", filters={"proyecto_id": p["id"]}, order="orden.asc")
        alcanzados = umbrales_cruzados(avance_mod.porcentaje(nodos))
        if not alcanzados:
            continue
        no_enviados = [u for u in alcanzados if not await _ya_tipo(db, f"hito_pct:{p['id']}:{u}")]
        if not no_enviados:
            continue
        top = max(no_enviados)  # celebra el más alto cruzado, sin ráfaga
        tokens = await _tokens(db)
        if not tokens:
            return {"hitos_pct": enviados, "sin_tokens": True}
        titulo, cuerpo = texto_hito_pct(p["nombre"], top)
        try:
            if await _push(db, tokens, titulo=titulo, cuerpo=cuerpo, payload=f"proyecto:{p['id']}"):
                # Marca TODOS los umbrales cruzados no enviados (incl. los menores)
                # para que no disparen después: un solo festejo, no goteo.
                for u in no_enviados:
                    await db.insert(
                        "planificacion_enviados",
                        {"tipo": f"hito_pct:{p['id']}:{u}", "fecha": local.date().isoformat()},
                    )
                enviados += 1
        except RuntimeError:
            return {"hitos_pct": enviados, "error": "fcm_no_config"}
    return {"hitos_pct": enviados}


async def revisar_estancamiento(db: Postgrest, *, ahora: datetime | None = None) -> dict:
    """Avisa de proyectos activos estancados (sin avance ≥ umbral), sin repetir
    seguido. Pregunta: ¿sigue, reajustamos o parqueamos?"""
    ahora = ahora or datetime.now(timezone.utc)
    local = ahora.astimezone(LIMA)
    cfg = await _cfg_nudges(db)
    if not _en_ventana(local, cfg):
        return {"estancamiento": 0, "fuera_de_ventana": True}
    # Las skills NO se avisan por estancamiento: un hobby puede dormir un tiempo
    # sin culpa. Solo los proyectos de trabajo reciben el «¿retomamos?».
    activos = creacion_proyecto.solo_proyectos(
        await db.list("proyectos", filters={"estado": "activo"})
    )
    enviados = 0
    for p in activos:
        info = estancado(p.get("ultima_actividad_en"), ahora=ahora)
        if not info["estancado"]:
            continue
        tipo = f"estancamiento:{p['id']}"
        desde = (local.date() - timedelta(days=DIAS_ENTRE_AVISOS_ESTANCAMIENTO)).isoformat()
        recientes = await db.list(
            "planificacion_enviados", raw_filters={"tipo": f"eq.{tipo}", "fecha": f"gte.{desde}"}, limit=1
        )
        if recientes:
            continue
        tokens = await _tokens(db)
        if not tokens:
            return {"estancamiento": enviados, "sin_tokens": True}
        titulo, cuerpo = texto_estancamiento(p["nombre"], info["dias"])
        try:
            if await _push(db, tokens, titulo=titulo, cuerpo=cuerpo, payload=f"proyecto:{p['id']}"):
                await db.insert("planificacion_enviados", {"tipo": tipo, "fecha": local.date().isoformat()})
                enviados += 1
        except RuntimeError:
            return {"estancamiento": enviados, "error": "fcm_no_config"}
    return {"estancamiento": enviados}


# ── Contexto holístico para el modelo (lo usa la tool revisar_proyecto) ──────

async def contexto_holistico(db: Postgrest, proyecto: dict[str, Any]) -> dict[str, Any]:
    """Todo el proyecto en una foto, para revisar/generar tareas SIN aislarse:
    árbol, %, fase a elaborar, ritmo, estancamiento, meta y criterios."""
    nodos = await db.list("arbol_nodos", filters={"proyecto_id": proyecto["id"]}, order="orden.asc")
    pct = avance_mod.porcentaje(nodos)
    ahora = datetime.now(timezone.utc)
    params = proyecto.get("parametros") or {}
    fase = fase_a_elaborar(nodos)
    est = estancado(proyecto.get("ultima_actividad_en"), ahora=ahora)
    cands = candidatos_proyecto(nodos)
    siguiente = cands[0].get("titulo") if cands else None
    # Re-scope honesto SOLO si está estancado (anti-abandono): achicar el paso.
    reescopeo = sugerir_reescopeo(siguiente) if est["estancado"] else None
    return {
        "proyecto": proyecto.get("nombre"),
        "porcentaje": pct,
        "objetivo": proyecto.get("objetivo"),
        "meta": params.get("meta_plazo"),
        "criterio_exito": params.get("criterio_exito"),
        "porque": params.get("porque"),
        "plan": avance_mod.desglose_por_fase(nodos),
        "fase_a_elaborar": (fase or {}).get("titulo"),
        "fase_a_elaborar_id": (fase or {}).get("id"),
        "siguiente_paso": siguiente,
        "estancamiento": est,
        "reescopeo_sugerido": reescopeo,
        "nodos_existentes": [n.get("titulo", "") for n in nodos],
    }


# ── Helpers ──────────────────────────────────────────────────────────────────

def _parse(valor: Any) -> datetime | None:
    if isinstance(valor, datetime):
        return valor if valor.tzinfo else valor.replace(tzinfo=timezone.utc)
    if not isinstance(valor, str) or not valor:
        return None
    try:
        d = datetime.fromisoformat(valor.replace("Z", "+00:00"))
    except ValueError:
        return None
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)


def _norm(s: Any) -> str:
    r = s.lower().strip() if isinstance(s, str) else ""
    con, sin = "áàäâãéèëêíìïîóòöôõúùüûñ", "aaaaaeeeeiiiiooooouuuun"
    for i in range(len(con)):
        r = r.replace(con[i], sin[i])
    return r
