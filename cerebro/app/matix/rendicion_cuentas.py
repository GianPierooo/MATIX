"""Rendición de cuentas: push directo del sistema con 3 botones de acción
cuando hay tareas sin completar.

Contenido DETERMINISTA (plantilla con datos inyectados, sin LLM, cero tokens).
Disparo: enganchado al ritual de "Cierre del día" + chequeos periódicos del
scheduler. Reusa de raíz:
  - `rollover.tareas_no_cumplidas` para detectar lo que quedó pendiente.
  - `horario.ventanas_libres` (con `buffer_pre_sueno_min`) para decidir si el
    botón "Aplázala más tarde hoy" se ofrece, basado en TU ancla de dormir.
  - `permitido_ahora` (silencio nocturno) y los anclas del usuario.
  - El `enviar_push` de FCM + el canal `matix_recordatorios` ya existentes.

Los 3 botones (la app los pinta con `flutter_local_notifications`, que SÍ
soporta `actions` con handler de tap que corre con la app cerrada):
  - "hecho"     → completar tarea (POST /tareas/{id}/accion-rendicion-cuentas)
  - "manana"    → rollover.aplicar_rollover(decision="otro_dia")
  - "mas_tarde" → mover al próximo hueco real de HOY (solo si hay ventana útil)

Escalada CON TOPE (anti-spam):
  nivel 1 = aviso suave (primer ping, al cierre o al pasar el plazo)
  nivel 2 = recordatorio firme (al día siguiente si sigue sin atender)
  nivel 3 = aviso final — tras este la tarea NO se vuelve a pingar.
Una tarea ya resuelta (`resuelta_en is not null`) se silencia para siempre.
"""
from __future__ import annotations

import asyncio
import logging
from datetime import date, datetime, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo

from ..db import Postgrest
from . import horario, recordatorios, rollover
from .push_fcm import TokenInvalido, enviar_push

logger = logging.getLogger("matix.rendicion_cuentas")

LIMA = ZoneInfo("America/Lima")

# Tope de tareas listadas en el cuerpo del push (evita textos gigantes).
MAX_TAREAS_LISTADAS = 3
# Tope de tareas que se mandan en UN tick (no abrir la pantalla con 20 pings).
MAX_TAREAS_POR_TICK = 5
# Niveles de escalada (1=suave, 2=firme, 3=final). Tope dura.
NIVEL_MAX = 3
# Espera entre niveles del MISMO tarea (no re-pingar antes de ~20h).
HORAS_ENTRE_NIVELES = 20


# ════════════════════════════════════════════════════════════════════════════
# PURO (testeable sin BD ni red)
# ════════════════════════════════════════════════════════════════════════════


def _titulo_corto(tarea: dict[str, Any]) -> str:
    """Título acotado a 40 chars (legible en la notificación)."""
    t = (tarea.get("titulo") or "Tarea").strip()
    return t if len(t) <= 40 else t[:37] + "…"


def armar_contenido(
    tareas: list[dict[str, Any]],
    *,
    nivel: int,
    hay_ventana_util: bool,
) -> dict[str, Any]:
    """Arma el contenido DETERMINISTA del push de rendición de cuentas.

    Devuelve `{titulo, cuerpo, acciones}` donde `acciones` es la lista de IDs
    que la app pinta como botones — en el orden visible. El botón "mas_tarde"
    aparece SOLO si `hay_ventana_util=True` (queda tiempo real antes de tu
    ancla de dormir para meter la tarea). PURO.
    """
    n = len(tareas)
    titulos = [_titulo_corto(t) for t in tareas[:MAX_TAREAS_LISTADAS]]
    sobra = max(0, n - MAX_TAREAS_LISTADAS)

    if n == 0:
        return {"titulo": "", "cuerpo": "", "acciones": []}

    # Tono escalado por nivel — más firme conforme insiste. Sin culpa, directo.
    if nivel <= 1:
        verbo = "No completaste"
        cierre = "¿Las hiciste?"
    elif nivel == 2:
        verbo = "Siguen sin hacerse"
        cierre = "¿Cómo va eso?"
    else:  # nivel 3 (final)
        verbo = "Tercer aviso"
        cierre = "Decide ya: ¿hecho, aplázala, o pasa?"

    if n == 1:
        titulo = "No completaste una tarea"
        lista = f"«{titulos[0]}»"
    else:
        titulo = f"No completaste {n} tareas"
        lista = ", ".join(f"«{t}»" for t in titulos)
        if sobra > 0:
            lista += f" y {sobra} más"

    cuerpo = f"{verbo}: {lista}. {cierre}"

    # Botones: "hecho" siempre primero (acción más valiosa), "mas_tarde" solo si
    # hay ventana útil, "manana" siempre como fallback seguro.
    acciones: list[str] = ["hecho"]
    if hay_ventana_util:
        acciones.append("mas_tarde")
    acciones.append("manana")

    return {"titulo": titulo, "cuerpo": cuerpo, "acciones": acciones}


def horas_entre_niveles(intensidad: str) -> int:
    """Cada cuántas horas se RE-ALERTA (sube de nivel) si la tarea sigue sin
    resolver, según la intensidad. Más intensa = insiste más seguido (la fuerza
    está en la insistencia, no en el tono). El tope de niveles (NIVEL_MAX) y el
    silencio nocturno siguen firmes — esto solo regula la cadencia. PURO."""
    return {
        "suave": 20,
        "medio": 12,
        "intenso": 6,
        "maximo": 3,
    }.get(intensidad, HORAS_ENTRE_NIVELES)


def calcular_nivel_siguiente(
    ultimo: dict[str, Any] | None,
    *,
    ahora: datetime,
    horas_cooldown: int = HORAS_ENTRE_NIVELES,
) -> int | None:
    """Devuelve el nivel del PRÓXIMO ping para esta tarea, o None si ya no se
    debe pingar (resuelta, o ya pasó el tope). PURO.

    - Sin pings previos             → nivel 1 (suave).
    - Último resuelto               → None (silencio definitivo).
    - Último < `horas_cooldown` atrás → None (cooldown, no spam).
    - Último nivel 3                → None (tope dura).
    - Lo demás                      → ultimo.nivel + 1.
    """
    if ultimo is None:
        return 1
    if ultimo.get("resuelta_en"):
        return None
    enviado = _parse_dt(ultimo.get("enviado_en"))
    if enviado is None:
        return None
    if (ahora - enviado) < timedelta(hours=horas_cooldown):
        return None
    nivel_prev = int(ultimo.get("nivel") or 0)
    if nivel_prev >= NIVEL_MAX:
        return None
    return nivel_prev + 1


def _parse_dt(v: Any) -> datetime | None:
    if isinstance(v, datetime):
        return v if v.tzinfo else v.replace(tzinfo=timezone.utc)
    if not isinstance(v, str) or not v:
        return None
    try:
        d = datetime.fromisoformat(v.replace("Z", "+00:00"))
    except ValueError:
        return None
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)


def hay_ventana_util_hoy(
    fijos: list[dict[str, Any]],
    *,
    ahora_local: datetime,
    despertar_min: int,
    dormir_min: int,
    buffer_min: int,
    buffer_pre_sueno_min: int,
    dur_min: int,
) -> bool:
    """¿Queda ventana útil real HOY (ahora..ancla_dormir - buffer) suficiente
    para una tarea de `dur_min` minutos? PURO. Reusa `ventanas_libres` de B.
    """
    desde = ahora_local.hour * 60 + ahora_local.minute
    ventanas = horario.ventanas_libres(
        fijos,
        despertar_min=despertar_min,
        dormir_min=dormir_min,
        buffer_min=buffer_min,
        desde_min=desde,
        buffer_pre_sueno_min=buffer_pre_sueno_min,
    )
    return any(v["dur"] >= dur_min for v in ventanas)


# ════════════════════════════════════════════════════════════════════════════
# IMPURO (orquesta BD + FCM)
# ════════════════════════════════════════════════════════════════════════════


async def _ultimos_pings(
    db: Postgrest, *, tarea_ids: list[str]
) -> dict[str, dict[str, Any]]:
    """Por cada tarea_id, el ping MÁS RECIENTE (resuelto o no)."""
    if not tarea_ids:
        return {}
    out: dict[str, dict[str, Any]] = {}
    # Una sola lectura amplia + reduce en memoria (la tabla es chica).
    rows = await db.list(
        "pings_rendicion_cuentas",
        raw_filters={"tarea_id": f"in.({','.join(tarea_ids)})"},
        limit=500,
    )
    for r in rows:
        tid = r["tarea_id"]
        prev = out.get(tid)
        if prev is None or _parse_dt(r["enviado_en"]) > _parse_dt(prev["enviado_en"]):
            out[tid] = r
    return out


async def _candidatas_a_pingar(
    db: Postgrest, *, ahora: datetime, horas_cooldown: int = HORAS_ENTRE_NIVELES
) -> list[tuple[dict[str, Any], int]]:
    """Tareas no cumplidas que toca pingar AHORA con su nivel siguiente.
    Aplica dedup por nivel y tope (NIVEL_MAX). El `horas_cooldown` (cadencia de
    re-alerta) lo fija la intensidad."""
    tareas = await db.list(
        "tareas",
        raw_filters={"eliminado_en": "is.null", "completada": "is.false"},
        limit=500,
    )
    pendientes = rollover.tareas_no_cumplidas(tareas, ahora)
    if not pendientes:
        return []
    ultimos = await _ultimos_pings(db, tarea_ids=[t["id"] for t in pendientes])
    out: list[tuple[dict[str, Any], int]] = []
    for t in pendientes:
        nivel = calcular_nivel_siguiente(
            ultimos.get(t["id"]), ahora=ahora, horas_cooldown=horas_cooldown
        )
        if nivel is not None:
            out.append((t, nivel))
        if len(out) >= MAX_TAREAS_POR_TICK:
            break
    return out


async def revisar_rendicion_cuentas(
    db: Postgrest, *, ahora: datetime | None = None
) -> dict[str, Any]:
    """Un tick: detecta lo no cumplido, respeta el silencio nocturno, dedupea
    por tarea con escalada con tope, y manda UN push agregado con los botones
    de acción. Best-effort: nunca tumba al scheduler."""
    ahora = ahora or datetime.now(timezone.utc)
    local = ahora.astimezone(LIMA)

    # Silencio nocturno: reusamos la misma fuente que los nudges (config_nudges
    # → ancla del usuario). Si está en silencio, este tick no manda nada (ni el
    # modo máximo dispara full-screen mientras duermes).
    cfgs = await db.list("config_nudges", limit=1)
    cfg_nudges = cfgs[0] if cfgs else None
    if cfg_nudges and not recordatorios.permitido_ahora(local, cfg_nudges):
        return {"pings": 0, "silencio": True}
    intensidad = str((cfg_nudges or {}).get("intensidad") or "intenso")

    candidatas = await _candidatas_a_pingar(
        db, ahora=ahora, horas_cooldown=horas_entre_niveles(intensidad)
    )
    if not candidatas:
        return {"pings": 0}

    # Ventana útil HOY: reusa el buffer pre-sueño y los anclas (B). Si no
    # queda, el botón "más tarde" no se ofrece.
    cfg_h = await horario._config(db)
    fecha = local.date()
    fijos = await horario._compromisos_fijos(
        db, fecha=fecha, anclas=cfg_h.get("anclas") or []
    )
    hay_util = hay_ventana_util_hoy(
        fijos,
        ahora_local=local,
        despertar_min=int(cfg_h["hora_despertar"]) * 60,
        dormir_min=int(cfg_h["hora_dormir"]) * 60,
        buffer_min=int(cfg_h["buffer_min"]),
        buffer_pre_sueno_min=int(cfg_h.get("buffer_pre_sueno_min", 0) or 0),
        dur_min=int(cfg_h.get("dur_tarea_min", 20)),
    )

    # El nivel del push agregado es el MÁXIMO entre las candidatas (refleja la
    # urgencia más alta; el contenido es uniforme para todas).
    tareas_solo = [t for t, _ in candidatas]
    nivel_efectivo = max(n for _, n in candidatas)
    contenido = armar_contenido(
        tareas_solo, nivel=nivel_efectivo, hay_ventana_util=hay_util
    )
    if not contenido["acciones"]:
        return {"pings": 0}

    # Mandamos a TODOS los tokens (un solo dispositivo en privado, pero la lista
    # permite el caso multi-device limpiamente). Tokens muertos se purgan.
    tokens = [t["token"] for t in await db.list("device_tokens", limit=100)]
    if not tokens:
        return {"pings": 0, "sin_tokens": True}

    # Para que la app pueda actuar por tarea desde los botones sin abrir UI,
    # mandamos la lista de tarea_ids en el data del push.
    data = {
        "payload": "rendicion_cuentas",
        "tipo": "rendicion_cuentas",
        "tareas_ids": ",".join(t["id"] for t in tareas_solo),
        "tareas_titulos": "||".join(_titulo_corto(t) for t in tareas_solo),
        "acciones": ",".join(contenido["acciones"]),
        "nivel": str(nivel_efectivo),
        # La app mapea la intensidad al mecanismo Android (heads-up /
        # persistente / full-screen). `critico` = tarea vencida en el último
        # nivel: SOLO esto habilita el full-screen del modo máximo.
        "intensidad": intensidad,
        "critico": "true" if nivel_efectivo >= NIVEL_MAX else "false",
    }
    enviados_ok = 0
    for tok in list(tokens):
        try:
            await asyncio.to_thread(
                enviar_push,
                tok,
                titulo=contenido["titulo"],
                cuerpo=contenido["cuerpo"],
                data=data,
            )
            enviados_ok += 1
        except TokenInvalido:
            filas = await db.list("device_tokens", filters={"token": tok}, limit=1)
            if filas:
                await db.delete("device_tokens", filas[0]["id"])
            tokens.remove(tok)
        except RuntimeError as e:
            logger.error("rendicion_cuentas: FCM no configurado (%s)", e)
            return {"pings": 0, "error": "fcm_no_config"}
        except Exception:  # noqa: BLE001
            logger.exception("rendicion_cuentas: fallo mandando push")

    if enviados_ok == 0:
        return {"pings": 0, "tokens_fallidos": True}

    # Registramos un ping por tarea (lo que dedupea las próximas pasadas).
    for t, nivel in candidatas:
        try:
            await db.insert(
                "pings_rendicion_cuentas",
                {"tarea_id": t["id"], "nivel": nivel},
            )
        except Exception:  # noqa: BLE001
            logger.exception("rendicion_cuentas: no pude registrar ping de tarea")

    return {
        "pings": len(candidatas),
        "nivel": nivel_efectivo,
        "hay_ventana_util": hay_util,
    }


async def marcar_resuelta(
    db: Postgrest, *, tarea_id: str, accion: str, ahora: datetime | None = None
) -> None:
    """Marca el último ping NO resuelto de una tarea como resuelto. Idempotente:
    si no hay ping abierto, no hace nada (el endpoint igual aplica la acción).
    """
    ahora = ahora or datetime.now(timezone.utc)
    rows = await db.list(
        "pings_rendicion_cuentas",
        raw_filters={"tarea_id": f"eq.{tarea_id}", "resuelta_en": "is.null"},
        limit=10,
    )
    for r in rows:
        await db.update(
            "pings_rendicion_cuentas",
            r["id"],
            {"resuelta_en": ahora.isoformat(), "accion": accion},
        )


def proximo_slot_hoy_min(
    fijos: list[dict[str, Any]],
    *,
    ahora_local: datetime,
    despertar_min: int,
    dormir_min: int,
    buffer_min: int,
    buffer_pre_sueno_min: int,
    dur_min: int,
) -> int | None:
    """Inicio (en minutos desde medianoche, hora Lima) del PRIMER hueco real
    de hoy que cabe `dur_min` antes del ancla de dormir (menos buffer). PURO.
    None si ya no hay ventana útil. Lo usa la acción "más tarde hoy"."""
    desde = ahora_local.hour * 60 + ahora_local.minute
    ventanas = horario.ventanas_libres(
        fijos,
        despertar_min=despertar_min,
        dormir_min=dormir_min,
        buffer_min=buffer_min,
        desde_min=desde,
        buffer_pre_sueno_min=buffer_pre_sueno_min,
    )
    for v in ventanas:
        if v["dur"] >= dur_min:
            # Pequeño margen para no chocar con `desde` (ya viene aplicado por
            # ventanas_libres, así que devolvemos `ini` directo).
            return v["ini"]
    return None
