"""Motor de proactividad (Capa 8).

Matix se ADELANTA: en el tick del scheduler que ya existe evalúa gatillos
anticipatorios, decide lo más valioso/oportuno/relevante AHORA y, con frenos
firmes, manda UN aviso accionable por push. No es un recordatorio más: es
iniciativa propia, dosificada.

GATILLOS (anticipatorios):
- pre_libre   — un rato antes de que se abra un bloque libre, ofrece qué hacer.
- reposicion  — cuando a un proyecto le quedan pocas tareas de corto plazo,
                genera el siguiente lote (reusa la siembra progresiva) y lo
                propone DÍAS antes; nunca te deja "sin acción siguiente".
- deadline    — heads-up anticipado en la zona media (1 día..horizonte del
                nivel); las últimas 24 h las maneja el motor de nudges (no
                duplicamos).
- hueco       — si justo ahora hay un rato no planificado, sugerencia opcional.

DECISIÓN: puntúa cada candidato (valor = urgencia × oportunidad × relevancia),
opera sobre TODOS los proyectos y skills activos, y rutea el JUICIO al modelo
fuerte cuando hay empate alto (best-effort; si no, gana el puntaje).

CONTENCIÓN (no negociable, incluso en EXIGENTE):
- tope de avisos proactivos al día (por nivel),
- dedup por TEMA (un tema se avisa una vez al día),
- adaptación al ritmo: si se ignora, BAJA el volumen (no apila),
- skills con toque ligero,
- respeta el silencio y la ventana de disponibilidad (reusa config_nudges).

La parte PURA (params por nivel, gatillos, tope, ritmo, dedup, puntaje, textos)
está separada y se testea sin BD ni FCM.
"""
from __future__ import annotations

import logging
import re
from datetime import date, datetime, timezone
from typing import Any
from zoneinfo import ZoneInfo

from ..db import Postgrest

logger = logging.getLogger("matix.proactividad")

LIMA = ZoneInfo("America/Lima")


# ════════════════════════════════════════════════════════════════════════════
# LÓGICA PURA (testeable sin BD)
# ════════════════════════════════════════════════════════════════════════════

# El DIAL: cuán proactivo. Arranca EXIGENTE (proactivo y encima) pero con tope
# firme. Cada nivel define cuántos avisos al día y qué gatillos entran.
NIVELES: dict[str, dict[str, Any]] = {
    "suave": {
        "tope_diario": 2,
        "deadline_horizonte_h": 0,    # suave no hace heads-up de plazos
        "incluir_hueco": False,
        "incluir_pre_libre": True,
    },
    "equilibrado": {
        "tope_diario": 4,
        "deadline_horizonte_h": 48,
        "incluir_hueco": False,
        "incluir_pre_libre": True,
    },
    "exigente": {
        "tope_diario": 7,
        "deadline_horizonte_h": 72,
        "incluir_hueco": True,
        "incluir_pre_libre": True,
    },
}


def params_nivel(nivel: str | None) -> dict[str, Any]:
    """Parámetros del nivel (default EXIGENTE si llega algo raro). PURO."""
    return NIVELES.get((nivel or "").strip().lower(), NIVELES["exigente"])


def proximo_hueco_libre(
    bloques: list[dict[str, int]], ahora_min: int, *, lead_min: int, min_util: int = 30
) -> dict[str, int] | None:
    """El próximo hueco LIBRE entre bloques cuyo inicio cae dentro de la ventana
    de anticipación (0..lead_min desde ahora) y dura al menos `min_util`. Cada
    bloque es {'ini','fin'} en minutos. Devuelve {'ini','dur'} o None. PURO."""
    bs = sorted(bloques, key=lambda b: b["ini"])
    for i in range(1, len(bs)):
        fin_prev = bs[i - 1]["fin"]
        ini_sig = bs[i]["ini"]
        dur = ini_sig - fin_prev
        if dur < min_util:
            continue
        delta = fin_prev - ahora_min  # cuánto falta para que empiece el hueco
        if 0 <= delta <= lead_min:
            return {"ini": fin_prev, "dur": dur}
    return None


def hueco_actual(
    bloques: list[dict[str, int]], ahora_min: int, dormir_min: int, *, min_util: int = 30
) -> dict[str, int] | None:
    """¿Estoy AHORA en un rato no planificado? Si ningún bloque cubre `ahora` y
    hasta el próximo bloque (o la hora de dormir) queda al menos `min_util`,
    devuelve {'ini','dur'}; si no, None. PURO."""
    bs = sorted(bloques, key=lambda b: b["ini"])
    for b in bs:
        if b["ini"] <= ahora_min < b["fin"]:
            return None  # ocupado
    siguiente = min((b["ini"] for b in bs if b["ini"] > ahora_min), default=dormir_min)
    fin = min(siguiente, dormir_min)
    dur = fin - ahora_min
    if dur >= min_util:
        return {"ini": ahora_min, "dur": dur}
    return None


def necesita_reposicion(abiertas: int, *, umbral: int = 1) -> bool:
    """¿El proyecto se está quedando sin acción de corto plazo? PURO."""
    return abiertas <= umbral


def hay_grueso_pendiente(nodos: list[dict[str, Any]]) -> bool:
    """¿Quedan fases GRUESAS (por desglosar) sin cerrar? Señal de "fase por
    cerrar / toca planear lo siguiente". PURO."""
    return any(
        n.get("granularidad") == "grueso" and n.get("estado") != "hecho"
        for n in nodos
    )


def urgencia_deadline(horas_restantes: float, *, horizonte_h: int) -> str | None:
    """Heads-up ANTICIPADO de plazo, solo en la zona media: entre ~1 día y el
    horizonte del nivel. Las últimas 24 h las maneja el motor de nudges (no
    duplicamos). None = no avisar proactivamente. PURO."""
    if horizonte_h <= 0:
        return None
    if horas_restantes <= 24:
        return None  # zona del motor de nudges
    if horas_restantes <= horizonte_h:
        return "pronto"
    return None


def dentro_de_tope(enviados_hoy: int, tope: int) -> bool:
    """¿Queda cupo de avisos proactivos hoy? PURO."""
    return enviados_hoy < tope


def tope_ajustado_por_ritmo(
    tope_base: int, enviados_recientes: int, acciones_recientes: int
) -> int:
    """Adaptación al ritmo (anti-apilar): si insistí y NO hubo acción, RECORTO el
    tope; nunca lo subo. La urgencia activa, no estresa. PURO."""
    if enviados_recientes >= 3 and acciones_recientes == 0:
        return max(1, tope_base // 3)
    if enviados_recientes >= 5 and acciones_recientes <= 1:
        return max(1, tope_base // 2)
    return tope_base


def clave_dedup(tipo: str, ref: str) -> str:
    """Clave de dedup por TEMA del día. PURO."""
    return f"{tipo}:{ref}"


def puntuar(candidato: dict[str, Any]) -> float:
    """Valor del candidato = urgencia × oportunidad × relevancia. PURO."""
    return float(
        candidato.get("urgencia", 1)
        * candidato.get("oportunidad", 1)
        * candidato.get("relevancia", 1)
    )


def _dur_txt(min_: int) -> str:
    h, m = divmod(int(min_), 60)
    if h and m:
        return f"{h}h{m:02d}"
    if h:
        return f"{h}h"
    return f"{m}min"


def texto_pre_libre(dur_min: int, sugerencia: str) -> tuple[str, str]:
    """Aviso anticipado de rato libre (PURO)."""
    return (
        "Pronto tienes un rato",
        f"Se te abre un hueco de {_dur_txt(dur_min)}. ¿Le metes a {sugerencia}? "
        "Tócame para verlo.",
    )


def texto_hueco(dur_min: int, sugerencia: str) -> tuple[str, str]:
    """Sugerencia opcional para un rato libre AHORA (PURO)."""
    return (
        "Tienes un rato ahora",
        f"Estás con ~{_dur_txt(dur_min)} libres. Si quieres, aprovecha con "
        f"{sugerencia}.",
    )


def texto_reposicion_lote(proyecto: str, primer_paso: str) -> tuple[str, str]:
    """Generé el siguiente lote días antes (PURO)."""
    return (
        "Te dejé lo siguiente listo",
        f"A {proyecto} le quedaban pocas, así que ya preparé el siguiente paso: "
        f"{primer_paso}. Tócame para arrancarlo.",
    )


def texto_reposicion_fase(proyecto: str) -> tuple[str, str]:
    """Fase por cerrar: toca planear lo que sigue (PURO)."""
    return (
        "Casi cierras una fase",
        f"{proyecto} está por cerrar una fase. Planeemos lo que sigue para que "
        "no te quedes sin acción.",
    )


def texto_deadline(titulo: str, horas: float) -> tuple[str, str]:
    """Heads-up anticipado de un plazo (PURO)."""
    dias = int(horas // 24)
    cuando = f"{dias} día(s)" if dias >= 1 else f"{int(horas)} h"
    return (
        f"Se viene: {titulo}",
        f"Vence en ~{cuando}. Mejor adelantarlo un poco y no correr al final.",
    )


# ════════════════════════════════════════════════════════════════════════════
# Orquestación (impura): lee tablas, decide y manda UN aviso. Best-effort.
# ════════════════════════════════════════════════════════════════════════════

_SYS_JUEZ = (
    "Eres el juez de proactividad de Matix. Te doy candidatos de aviso para el "
    "usuario AHORA. Elige el más valioso, oportuno y relevante (no el más "
    "ruidoso). Responde SOLO con el número del elegido, nada más."
)


async def _config(db: Postgrest) -> dict[str, Any]:
    try:
        filas = await db.list("config_proactividad", limit=1)
    except Exception:  # noqa: BLE001
        return {}
    return filas[0] if filas else {}


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


async def _acciones_recientes(db: Postgrest, hoy: date) -> int:
    """Proxy de "sí te hago caso": items del set cerrados hoy + tareas completadas
    hoy. Sirve a la adaptación al ritmo."""
    n = 0
    try:
        items = await db.list("set_diario_items", filters={"fecha": hoy.isoformat()})
        n += sum(1 for i in items if i.get("estado") == "hecho")
    except Exception:  # noqa: BLE001
        pass
    return n


async def _sugerencia_para_hueco(db: Postgrest, plan: dict, dur: int) -> str:
    """Qué ofrecer en un hueco: del pool de sugerencias del plan (FIX 3) la más
    grande que quepa; si no hay, una práctica de skill rotada por el día."""
    pool = [s for s in (plan.get("sugerencias") or []) if int(s.get("dur_min", 30)) <= dur]
    pool.sort(key=lambda s: int(s.get("dur_min", 30)), reverse=True)
    if pool:
        return pool[0].get("titulo") or "algo de tus proyectos"
    # Fallback: una skill activa, rotando por el día (toque ligero).
    try:
        from . import creacion_proyecto, planificador_diario

        skills = creacion_proyecto.solo_skills(
            await db.list("proyectos", filters={"estado": "activo"})
        )
        if skills:
            sk = planificador_diario.elegir_skill_del_dia(skills, date.today().toordinal())
            if sk:
                return f"Práctica: {sk['nombre']}"
    except Exception:  # noqa: BLE001
        pass
    return "algo de tus proyectos"


async def _candidatos(
    db: Postgrest, *, ahora: datetime, local: datetime, cfg: dict, par: dict,
) -> list[dict[str, Any]]:
    """Reúne candidatos de todos los gatillos sobre TODOS los proyectos y skills
    activos. Cada candidato: {tipo, clave, titulo, cuerpo, payload, urgencia,
    oportunidad, relevancia}. Best-effort por gatillo (uno que falle no tumba al
    resto)."""
    from . import creacion_proyecto, horario, planificador_diario, siembra_tareas

    out: list[dict[str, Any]] = []
    fecha = local.date()

    # ── Rollover: lo no cumplido (cuando algo se pasó de su hora) ──────────────
    # No lo deja morir callado: nudgea a revisar lo que quedó sin hacer. La
    # propuesta tocable (acepto / otro día / lo suelto) la sirve /rollover y la
    # surfacea el robot; acá solo gatillamos el aviso dosificado. Si hay
    # sobrecarga, el cuerpo lleva el mensaje honesto (no más "te lo muevo").
    try:
        from . import rollover

        tareas_nc = await db.list(
            "tareas",
            raw_filters={"eliminado_en": "is.null", "completada": "is.false"},
            limit=500,
        )
        no_cumplidas = rollover.tareas_no_cumplidas(tareas_nc, ahora)
        if no_cumplidas:
            sob = rollover.evaluar_sobrecarga([
                {"titulo": t.get("titulo"),
                 "veces_reprogramada": t.get("veces_reprogramada")}
                for t in no_cumplidas
            ])
            tt, cuerpo = rollover.texto_aviso_rollover(len(no_cumplidas), sob)
            out.append({
                "tipo": "rollover",
                "clave": clave_dedup("rollover", fecha.isoformat()),
                "titulo": tt, "cuerpo": cuerpo, "payload": "rollover",
                "urgencia": 3, "oportunidad": 2, "relevancia": 3,
            })
    except Exception:  # noqa: BLE001
        logger.exception("proactividad: gatillo rollover falló")

    # ── Deadline (anticipado, zona media; <24h lo maneja nudges) ──────────────
    try:
        horizonte = int(par.get("deadline_horizonte_h", 0))
        if horizonte > 0:
            tareas = await db.list(
                "tareas",
                raw_filters={
                    "vence_en": "not.is.null",
                    "completada": "is.false",
                    "eliminado_en": "is.null",
                },
                limit=500,
            )
            for t in tareas:
                vence = _parse_dt(t.get("vence_en"))
                if vence is None:
                    continue
                horas = (vence - ahora).total_seconds() / 3600
                if urgencia_deadline(horas, horizonte_h=horizonte) is None:
                    continue
                titulo = (t.get("titulo") or "tu tarea").strip()
                tt, cuerpo = texto_deadline(titulo, horas)
                out.append({
                    "tipo": "deadline",
                    "clave": clave_dedup("deadline", str(t["id"])),
                    "titulo": tt, "cuerpo": cuerpo,
                    "payload": f"tarea:{t['id']}",
                    "urgencia": 3, "oportunidad": 2, "relevancia": 3,
                })
    except Exception:  # noqa: BLE001
        logger.exception("proactividad: gatillo deadline falló")

    # ── Reposición (genera el siguiente lote DÍAS antes; nunca sin acción) ────
    try:
        proyectos = creacion_proyecto.solo_proyectos(
            await db.list("proyectos", filters={"estado": "activo"})
        )
        for p in proyectos:
            pid = p["id"]
            abiertas = await db.list(
                "tareas",
                raw_filters={
                    "proyecto_id": f"eq.{pid}",
                    "completada": "is.false",
                    "eliminado_en": "is.null",
                },
                limit=50,
            )
            if not necesita_reposicion(len(abiertas)):
                continue
            nodos = await db.list("arbol_nodos", filters={"proyecto_id": pid}, order="orden.asc")
            disponibles = siembra_tareas.nodos_inmediatos(nodos)
            if disponibles:
                # Genera el siguiente lote (siembra progresiva del motor) y lo propone.
                res = await siembra_tareas.sembrar_inmediatas(db, p, maximo=2)
                if res.get("creadas"):
                    tt, cuerpo = texto_reposicion_lote(
                        p.get("nombre", "tu proyecto"), disponibles[0].get("titulo", "el siguiente paso")
                    )
                    out.append({
                        "tipo": "reposicion",
                        "clave": clave_dedup("reposicion", str(pid)),
                        "titulo": tt, "cuerpo": cuerpo,
                        "payload": f"proyecto:{pid}",
                        "urgencia": 2, "oportunidad": 2, "relevancia": 3,
                    })
            elif hay_grueso_pendiente(nodos):
                tt, cuerpo = texto_reposicion_fase(p.get("nombre", "tu proyecto"))
                out.append({
                    "tipo": "reposicion",
                    "clave": clave_dedup("reposicion", str(pid)),
                    "titulo": tt, "cuerpo": cuerpo,
                    "payload": f"proyecto:{pid}",
                    "urgencia": 2, "oportunidad": 2, "relevancia": 3,
                })
    except Exception:  # noqa: BLE001
        logger.exception("proactividad: gatillo reposicion falló")

    # ── Pre-libre / hueco (necesitan el plan del día) ─────────────────────────
    try:
        plan = await horario.plan_de_hoy_data(db, ahora=ahora, desde_ahora=True)
        bloques = [
            {"ini": horario.hhmm_a_min(b["inicio"]) or 0, "fin": horario.hhmm_a_min(b["fin"]) or 0}
            for b in plan.get("bloques", [])
        ]
        ahora_min = local.hour * 60 + local.minute
        dormir_min = horario.hhmm_a_min(plan.get("duerme") or "23:00") or (23 * 60)

        if par.get("incluir_pre_libre", True):
            lead = int(cfg.get("lead_libre_min", 30))
            hueco = proximo_hueco_libre(bloques, ahora_min, lead_min=lead)
            if hueco:
                sug = await _sugerencia_para_hueco(db, plan, hueco["dur"])
                tt, cuerpo = texto_pre_libre(hueco["dur"], sug)
                out.append({
                    "tipo": "pre_libre",
                    "clave": clave_dedup("pre_libre", horario.min_a_hhmm(hueco["ini"])),
                    "titulo": tt, "cuerpo": cuerpo, "payload": "hoy",
                    "urgencia": 1, "oportunidad": 3, "relevancia": 2,
                })

        if par.get("incluir_hueco", False):
            ahora_libre = hueco_actual(bloques, ahora_min, dormir_min)
            if ahora_libre:
                sug = await _sugerencia_para_hueco(db, plan, ahora_libre["dur"])
                tt, cuerpo = texto_hueco(ahora_libre["dur"], sug)
                out.append({
                    "tipo": "hueco",
                    "clave": clave_dedup("hueco", horario.min_a_hhmm(ahora_libre["ini"] // 30 * 30)),
                    "titulo": tt, "cuerpo": cuerpo, "payload": "hoy",
                    "urgencia": 1, "oportunidad": 2, "relevancia": 1,
                })
    except Exception:  # noqa: BLE001
        logger.exception("proactividad: gatillo pre_libre/hueco falló")

    return out


async def _elegir(db: Postgrest, candidatos: list[dict], *, local: datetime) -> dict:
    """De los candidatos (ya ordenados por puntaje desc) elige UNO. Si hay un
    líder claro, gana el puntaje (no gastamos el modelo). Si dos van parejos,
    rutea el JUICIO al modelo fuerte. Best-effort: ante cualquier fallo, gana el
    puntaje."""
    if len(candidatos) < 2:
        return candidatos[0]
    if puntuar(candidatos[0]) >= puntuar(candidatos[1]) * 1.4:
        return candidatos[0]
    try:
        from . import llm, modelos_llm

        _, fuerte = await modelos_llm.par_barato_fuerte(db)
        opciones = "\n".join(
            f"{i}. [{c['tipo']}] {c['titulo']} — {c['cuerpo']}"
            for i, c in enumerate(candidatos[:4])
        )
        msg = [
            {"role": "system", "content": _SYS_JUEZ},
            {"role": "user", "content": (
                f"Hora local: {local:%H:%M} ({local:%A}). Candidatos:\n{opciones}\n"
                "Responde solo el número."
            )},
        ]
        r = await llm.responder(msg, model=fuerte, temperature=0)
        m = re.search(r"\d+", r or "")
        if m:
            idx = int(m.group())
            if 0 <= idx < len(candidatos):
                return candidatos[idx]
    except Exception:  # noqa: BLE001
        logger.exception("proactividad: juicio con modelo fuerte falló; uso el puntaje")
    return candidatos[0]


async def revisar_proactividad(db: Postgrest, *, ahora: datetime | None = None) -> dict:
    """Un tick del motor de proactividad. Best-effort: nunca lanza. Manda a lo
    más UN aviso (el más valioso), respetando silencio, tope diario (ajustado al
    ritmo) y dedup por tema. Como corre cada minuto y el tope es diario, dosifica
    solo a lo largo del día."""
    ahora = ahora or datetime.now(timezone.utc)
    cfg = await _config(db)
    if not cfg or not cfg.get("activo"):
        return {"proactividad": 0, "off": True}
    nivel = cfg.get("nivel", "exigente")
    par = params_nivel(nivel)
    local = ahora.astimezone(LIMA)

    # Silencio / ventana de disponibilidad: reusa el motor de nudges.
    from . import planificador_diario, recordatorios

    ncfgs = await db.list("config_nudges", limit=1)
    if ncfgs and not recordatorios.permitido_ahora(local, ncfgs[0]):
        return {"proactividad": 0, "fuera_de_ventana": True}

    fecha = local.date()
    enviados = await db.list("proactividad_enviados", filters={"fecha": fecha.isoformat()})
    claves_hoy = {e.get("clave") for e in enviados}
    acciones = await _acciones_recientes(db, fecha)
    tope = tope_ajustado_por_ritmo(int(par["tope_diario"]), len(enviados), acciones)
    if not dentro_de_tope(len(enviados), tope):
        return {"proactividad": 0, "tope": True}

    candidatos = await _candidatos(db, ahora=ahora, local=local, cfg=cfg, par=par)
    candidatos = [c for c in candidatos if c["clave"] not in claves_hoy]
    if not candidatos:
        return {"proactividad": 0, "sin_candidatos": True}

    candidatos.sort(key=puntuar, reverse=True)
    elegido = await _elegir(db, candidatos, local=local)

    tokens = await planificador_diario._tokens(db)
    if not tokens:
        return {"proactividad": 0, "sin_tokens": True}
    try:
        ok = await planificador_diario._push(
            db, tokens, titulo=elegido["titulo"], cuerpo=elegido["cuerpo"],
            payload=elegido["payload"],
        )
        if ok:
            await db.insert("proactividad_enviados", {
                "tipo": elegido["tipo"], "clave": elegido["clave"],
                "fecha": fecha.isoformat(),
            })
            logger.info("proactividad: aviso %s enviado", elegido["tipo"])
            return {"proactividad": 1, "tipo": elegido["tipo"]}
    except RuntimeError:
        return {"proactividad": 0, "error": "fcm_no_config"}
    return {"proactividad": 0}
