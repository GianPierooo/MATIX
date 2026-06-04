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
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo

from ..db import Postgrest
from . import avance as avance_mod
from .planificador_diario import LIMA, _push, _tokens

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


def texto_checkin() -> tuple[str, str]:
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
    if not await db.list("proyectos", filters={"estado": "activo"}, limit=1):
        return {"checkin": 0, "sin_activos": True}
    semana = (local.date() - timedelta(days=local.isoweekday() - 1)).isoformat()
    if await _ya(db, "checkin", semana):
        return {"checkin": 0, "ya": True}
    tokens = await _tokens(db)
    if not tokens:
        return {"checkin": 0, "sin_tokens": True}
    titulo, cuerpo = texto_checkin()
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


async def revisar_estancamiento(db: Postgrest, *, ahora: datetime | None = None) -> dict:
    """Avisa de proyectos activos estancados (sin avance ≥ umbral), sin repetir
    seguido. Pregunta: ¿sigue, reajustamos o parqueamos?"""
    ahora = ahora or datetime.now(timezone.utc)
    local = ahora.astimezone(LIMA)
    cfg = await _cfg_nudges(db)
    if not _en_ventana(local, cfg):
        return {"estancamiento": 0, "fuera_de_ventana": True}
    activos = await db.list("proyectos", filters={"estado": "activo"})
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
        "estancamiento": est,
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
