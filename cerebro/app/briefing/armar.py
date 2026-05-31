"""Arma el briefing matutino del día (Capa 8 reducida · Paso 1).

Lógica: leer del hub lo que pasa hoy, agregarlo en secciones útiles
para alguien que se está levantando, y producir además un texto en
prosa apto para TTS (la app lo manda al endpoint de voz).

Decisiones (ver `docs/Plan_Capa8.md`):

- Sin LLM. Texto estructurado. Predecible, sin costo cada mañana.
- Reusa la lógica de zona horaria de `matix/contexto.py` (Lima,
  UTC-5) sin importar de allí para no acoplar al system prompt.
- Devuelve un dict con todas las secciones; la app decide qué pintar.
- Alertas en Paso 1: proyectos sin avance ≥3 días + choques de
  horario en la agenda de hoy. Más alertas en pasos siguientes.

Si el día está vacío (sin eventos, sin tareas hoy, sin alertas),
el saludo es "Hoy tienes la agenda libre" y las listas vienen vacías;
la app no debe forzar contenido inventado.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from ..db import Postgrest

# El usuario opera en Lima (UTC-5, sin DST). El cerebro corre en
# Railway con reloj UTC; explicitamos la conversión para no asumir
# nada del sistema.
_TZ_LIMA = timezone(timedelta(hours=-5))

# Umbral de "proyecto estancado" — días sin actividad para que
# entre en alertas del briefing.
_DIAS_PROYECTO_ESTANCADO = 3

# Cuántas tareas vencidas detallar en `texto_para_voz`. Más allá
# de esto, agregamos un cierre "… y N más antiguas".
_MAX_VENCIDAS_PROSA = 3


def _ahora_lima() -> datetime:
    return datetime.now(timezone.utc).astimezone(_TZ_LIMA)


def _a_lima(ts: str | None) -> datetime | None:
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone(_TZ_LIMA)
    except ValueError:
        return None


def _hh_mm(ts: str | None) -> str:
    """Devuelve `HH:MM` en hora local. Si el timestamp es inválido
    o nulo, devuelve cadena vacía — el caller decide cómo pintarlo."""
    dt = _a_lima(ts)
    return dt.strftime("%H:%M") if dt else ""


def _saludo_segun_hora(hora: int) -> str:
    """Saludo simple según la hora local del request. No lo
    parametrizamos por usuario — todavía es single-user."""
    if hora < 12:
        return "Buenos días"
    if hora < 19:
        return "Buenas tardes"
    return "Buenas noches"


def _dia_semana_es(dt: datetime) -> str:
    return [
        "lunes",
        "martes",
        "miércoles",
        "jueves",
        "viernes",
        "sábado",
        "domingo",
    ][dt.weekday()]


_MES_ES = [
    "enero",
    "febrero",
    "marzo",
    "abril",
    "mayo",
    "junio",
    "julio",
    "agosto",
    "septiembre",
    "octubre",
    "noviembre",
    "diciembre",
]


def _fecha_es(dt: datetime) -> str:
    return f"{_dia_semana_es(dt)} {dt.day} de {_MES_ES[dt.month - 1]}"


def _choques(eventos: list[dict[str, Any]]) -> list[tuple[dict, dict]]:
    """Pares de eventos del día cuyas franjas horarias se cruzan.
    Solo considera los que tienen `inicia_en` y `termina_en`."""
    pares: list[tuple[dict, dict]] = []
    franjas = []
    for e in eventos:
        if e.get("todo_el_dia"):
            continue
        ini = _a_lima(e.get("inicia_en"))
        fin = _a_lima(e.get("termina_en"))
        if not ini or not fin:
            continue
        franjas.append((ini, fin, e))
    franjas.sort(key=lambda f: f[0])
    for i, (ini_i, fin_i, ev_i) in enumerate(franjas):
        for j in range(i + 1, len(franjas)):
            ini_j, fin_j, ev_j = franjas[j]
            if ini_j >= fin_i:
                break
            pares.append((ev_i, ev_j))
    return pares


async def armar_briefing(db: Postgrest) -> dict[str, Any]:
    """Arma el briefing del día actual del usuario.

    Devuelve un dict serializable con todas las secciones más
    `resumen_corto` (para el body de la notificación) y
    `texto_para_voz` (para el botón TTS).
    """
    ahora = _ahora_lima()
    hoy = ahora.date()

    # ── Eventos de hoy (lectura directa, no van por contexto.py
    # para no acoplar — duplico 20 líneas de mapeo a cambio de
    # mantener el módulo de briefing autónomo).
    eventos_raw = await db.list(
        "eventos", raw_filters={"eliminado_en": "is.null"}
    )
    eventos_hoy_raw: list[dict[str, Any]] = []
    for e in eventos_raw:
        ini = _a_lima(e.get("inicia_en"))
        if ini and ini.date() == hoy:
            eventos_hoy_raw.append(e)
    eventos_hoy_raw.sort(key=lambda e: e["inicia_en"])

    eventos = [
        {
            "hora": _hh_mm(e.get("inicia_en")),
            "hora_fin": _hh_mm(e.get("termina_en")),
            "titulo": e["titulo"],
            "ubicacion": e.get("ubicacion"),
            "todo_el_dia": bool(e.get("todo_el_dia")),
            "es_de_google": e.get("origen") == "google",
        }
        for e in eventos_hoy_raw
    ]

    # ── Tareas: hoy + vencidas. Excluimos completadas.
    tareas = await db.list(
        "tareas", raw_filters={"eliminado_en": "is.null"}
    )
    cursos = await db.list("cursos")
    nombre_curso = {c["id"]: c["nombre"] for c in cursos}

    proyectos = await db.list("proyectos")
    nombre_proyecto = {p["id"]: p["nombre"] for p in proyectos}

    tareas_hoy: list[dict[str, Any]] = []
    vencidas: list[dict[str, Any]] = []
    for t in tareas:
        if t.get("completada"):
            continue
        v = _a_lima(t.get("vence_en"))
        if not v:
            continue
        contexto = None
        if t.get("proyecto_id"):
            contexto = nombre_proyecto.get(t["proyecto_id"])
        elif t.get("curso_id"):
            contexto = nombre_curso.get(t["curso_id"])
        item = {
            "titulo": t["titulo"],
            "prioridad": t.get("prioridad") or "media",
            "contexto": contexto,
            "vence_en": v.isoformat(),
        }
        if v.date() == hoy:
            tareas_hoy.append(item)
        elif v.date() < hoy:
            vencidas.append({**item, "dias_vencida": (hoy - v.date()).days})

    # Orden: tareas de hoy primero las de alta prioridad.
    _prio_orden = {"alta": 0, "media": 1, "baja": 2}
    tareas_hoy.sort(key=lambda t: _prio_orden.get(t["prioridad"], 9))
    vencidas.sort(key=lambda t: -t["dias_vencida"])

    # ── Alertas: proyectos estancados + choques horarios.
    alertas: list[dict[str, str]] = []
    activos = [p for p in proyectos if p.get("estado") == "activo"]
    for p in activos:
        ult_raw = p.get("ultima_actividad_en")
        if not ult_raw:
            continue
        ult = _a_lima(ult_raw)
        if not ult:
            continue
        dias = (ahora - ult).days
        if dias >= _DIAS_PROYECTO_ESTANCADO:
            alertas.append(
                {
                    "tipo": "proyecto_estancado",
                    "mensaje": (
                        f"{p['nombre']} sin avance hace {dias} días"
                    ),
                }
            )

    for ev_a, ev_b in _choques(eventos_hoy_raw):
        alertas.append(
            {
                "tipo": "choque_horario",
                "mensaje": (
                    f"«{ev_a['titulo']}» se cruza con "
                    f"«{ev_b['titulo']}»"
                ),
            }
        )

    vencidas_resumen = {
        "total": len(vencidas),
        "mas_antigua_dias": vencidas[0]["dias_vencida"] if vencidas else 0,
    }

    resumen_corto = _resumen_corto(
        n_eventos=len(eventos),
        n_tareas_hoy=len(tareas_hoy),
        n_alertas=len(alertas),
    )

    texto_para_voz = _armar_texto_voz(
        saludo=_saludo_segun_hora(ahora.hour),
        fecha_es=_fecha_es(ahora),
        eventos=eventos,
        tareas_hoy=tareas_hoy,
        vencidas_resumen=vencidas_resumen,
        alertas=alertas,
    )

    return {
        "fecha": hoy.isoformat(),
        "dia_semana": _dia_semana_es(ahora),
        "saludo": _saludo_segun_hora(ahora.hour),
        "eventos": eventos,
        "tareas_hoy": tareas_hoy,
        "tareas_vencidas": vencidas_resumen,
        "alertas": alertas,
        "resumen_corto": resumen_corto,
        "texto_para_voz": texto_para_voz,
    }


def _resumen_corto(*, n_eventos: int, n_tareas_hoy: int, n_alertas: int) -> str:
    """Cuerpo de la notificación. Diseñado para encajar en una
    línea: "3 eventos · 5 tareas · 2 alertas". Si no hay nada,
    devolvemos un texto suave en vez de "0 eventos · 0 tareas"."""
    partes: list[str] = []
    if n_eventos:
        partes.append(f"{n_eventos} {'evento' if n_eventos == 1 else 'eventos'}")
    if n_tareas_hoy:
        partes.append(f"{n_tareas_hoy} {'tarea' if n_tareas_hoy == 1 else 'tareas'}")
    if n_alertas:
        partes.append(f"{n_alertas} {'alerta' if n_alertas == 1 else 'alertas'}")
    if not partes:
        return "Día libre"
    return " · ".join(partes)


def _armar_texto_voz(
    *,
    saludo: str,
    fecha_es: str,
    eventos: list[dict[str, Any]],
    tareas_hoy: list[dict[str, Any]],
    vencidas_resumen: dict[str, int],
    alertas: list[dict[str, str]],
) -> str:
    """Versión continua del briefing, lista para TTS. Frases cortas,
    sin markdown, números expresados como dígitos (la TTS de OpenAI
    los pronuncia bien)."""
    frases: list[str] = []
    frases.append(f"{saludo}. Hoy es {fecha_es}.")

    if not eventos and not tareas_hoy and not alertas:
        frases.append("Tienes la agenda libre.")
        if vencidas_resumen["total"]:
            n = vencidas_resumen["total"]
            d = vencidas_resumen["mas_antigua_dias"]
            frases.append(
                f"Quedan {n} {'tarea vencida' if n == 1 else 'tareas vencidas'}, "
                f"la más antigua de hace {d} {'día' if d == 1 else 'días'}."
            )
        return " ".join(frases)

    if eventos:
        cuenta = len(eventos)
        if cuenta == 1:
            ev = eventos[0]
            if ev["todo_el_dia"]:
                frases.append(f"Tienes un evento todo el día: {ev['titulo']}.")
            else:
                frases.append(
                    f"Tienes un evento a las {ev['hora']}: {ev['titulo']}."
                )
        else:
            frases.append(f"Tienes {cuenta} eventos en agenda.")
            for ev in eventos:
                if ev["todo_el_dia"]:
                    frases.append(f"Todo el día: {ev['titulo']}.")
                else:
                    frases.append(f"A las {ev['hora']}: {ev['titulo']}.")

    if tareas_hoy:
        cuenta = len(tareas_hoy)
        if cuenta == 1:
            t = tareas_hoy[0]
            sufijo = f" de {t['contexto']}" if t.get("contexto") else ""
            frases.append(f"Hoy vence: {t['titulo']}{sufijo}.")
        else:
            frases.append(f"Hoy vencen {cuenta} tareas.")
            for t in tareas_hoy[:4]:
                sufijo = f" de {t['contexto']}" if t.get("contexto") else ""
                frases.append(f"{t['titulo']}{sufijo}.")

    if vencidas_resumen["total"]:
        n = vencidas_resumen["total"]
        d = vencidas_resumen["mas_antigua_dias"]
        if n == 1:
            frases.append(f"Y arrastras 1 tarea vencida hace {d} días.")
        else:
            frases.append(
                f"Y arrastras {n} tareas vencidas, la más antigua hace "
                f"{d} {'día' if d == 1 else 'días'}."
            )

    if alertas:
        frases.append("Alertas:")
        for a in alertas[:3]:
            frases.append(a["mensaje"] + ".")

    return " ".join(frases)
