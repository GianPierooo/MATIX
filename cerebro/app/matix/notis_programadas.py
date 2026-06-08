"""Notis proactivas PROGRAMADAS — arma la lista de recordatorios que la app
debe meter en el scheduler local (`flutter_local_notifications.zonedSchedule`).

Por qué local-scheduling y NO push FCM tick a tick:
- Una vez programadas con el AlarmManager nativo, las dispara el SO aunque la
  app esté dormida. En MagicOS, donde el `ActionBroadcastReceiver` del plugin a
  veces no arranca, esto es lo más robusto: el sistema operativo entrega la
  noti directo, sin que el proceso de Matix tenga que estar vivo.
- Cero dependencia de FCM/red en el momento de disparar.
- Coste cero por día (no se envía push, no se llama LLM).

Tres tipos de noti programada (todas DETERMINISTAS, plantilla, cero LLM):

  1. `resumen_matutino` (1 al día) — al despertar (o a una hora early): el
     rundown del día listo para ojear ("hoy: 09:00 calistenia · 11:00 inglés…").
  2. `pre_actividad` (N al día) — `lead_min` minutos antes de cada bloque del
     plan ("en 15 min: práctica de guitarra"). Default 15 (override por
     `config_nudges.pre_actividad_min`).
  3. `nudge_proximo` (1-5 al día, según dial) — empujones que recuerdan LO
     SIGUIENTE pendiente en momentos clave del día (mediodía, tarde, etc.).
     El dial de intensidad dosifica cuántos.

Respeta de raíz:
- Quiet hours (`config_nudges.silencio_inicio/fin`): nada se PROGRAMA en esa
  ventana. Si una pre-actividad caería ahí, se omite.
- Dial de intensidad: el nº de `nudge_proximo` por día depende del dial.
- Dedup: cada noti lleva `dedup_key` estable (`tipo|fecha|hh:mm|ref`). La app
  cancela las anteriores con prefijo del día y vuelve a programar — re-pedir
  no duplica.

Este módulo es PURO (sin BD, sin red, sin reloj): recibe `plan_de_hoy_data` ya
calculado + `cfg_nudges` + `ahora`, y devuelve la lista. El router lo conecta.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, time, timedelta
from typing import Any, Literal
from zoneinfo import ZoneInfo

LIMA = ZoneInfo("America/Lima")

# Lead time default (minutos) para la noti pre-actividad.
LEAD_DEFAULT_MIN = 15

# Cuántos nudges del "próximo bloque" por día según el dial. 0 = el usuario en
# suave no quiere mucho ruido; en máximo Matix está encima.
NUDGES_PROXIMO_POR_DIAL: dict[str, int] = {
    "suave": 1,
    "medio": 2,
    "intenso": 3,
    "maximo": 5,
}

# Horas (Lima) donde se reparten los nudges del próximo bloque a lo largo del
# día. Es la "rejilla" en la que vamos colocando los pings; se quitan los
# que caigan en silencio o ya pasaron.
HORARIO_NUDGES = (11, 13, 15, 17, 19)


@dataclass(frozen=True)
class NotiProgramada:
    """Noti que la app debe meter al scheduler local. Serializable a dict para
    el JSON del endpoint."""
    tipo: Literal["resumen_matutino", "pre_actividad", "nudge_proximo"]
    dedup_key: str            # estable, identifica la noti del día
    disparar_en: datetime     # AWARE (UTC), la app convierte a su tz local
    titulo: str
    cuerpo: str
    payload: str              # acción al tocar (deep-link / launch). Pueden
                              # coincidir entre notis (el deep-link "abrir tu día"
                              # sirve para varias) — el dedup_key las diferencia.

    def to_dict(self) -> dict[str, Any]:
        return {
            "tipo": self.tipo,
            "dedup_key": self.dedup_key,
            "disparar_en": self.disparar_en.isoformat(),
            "titulo": self.titulo,
            "cuerpo": self.cuerpo,
            "payload": self.payload,
        }


# ── Helpers PUROS ────────────────────────────────────────────────────────────


def _hhmm_a_dt(hhmm: str, fecha: datetime) -> datetime | None:
    """Convierte 'HH:MM' (Lima) + fecha local → datetime aware UTC. Robusto a
    valores inválidos (devuelve None)."""
    try:
        h, m = hhmm.split(":")
        hi, mi = int(h), int(m)
        if not (0 <= hi <= 23 and 0 <= mi <= 59):
            return None
    except (ValueError, AttributeError):
        return None
    local = datetime(fecha.year, fecha.month, fecha.day, hi, mi, tzinfo=LIMA)
    return local.astimezone(tz=LIMA).astimezone(tz=fecha.tzinfo or LIMA).astimezone(tz=None) if False else local


def _en_silencio(local_hora: int, inicio: int, fin: int) -> bool:
    """Misma lógica que recordatorios._en_silencio (DRY: no podemos importar
    desde acá sin armar ciclo, así que la copiamos textualmente — 4 líneas)."""
    if inicio == fin:
        return False
    if inicio < fin:
        return inicio <= local_hora < fin
    return local_hora >= inicio or local_hora < fin  # cruza medianoche


def _en_silencio_dt(dt_local: datetime, cfg_nudges: dict[str, Any]) -> bool:
    """¿Cae `dt_local` (Lima) dentro del silencio nocturno?"""
    ini = int(cfg_nudges.get("silencio_inicio", 22))
    fin = int(cfg_nudges.get("silencio_fin", 8))
    return _en_silencio(dt_local.hour, ini, fin)


def _formatea_resumen(bloques: list[dict[str, Any]], max_items: int = 5) -> str:
    """Cuerpo del resumen matutino: "09:00 calistenia · 11:00 inglés · 18:00
    taller · +2". Mantiene CORTO (~110 chars) para que entre en la línea de la
    noti. Solo bloques con `inicio` definida (fijos y tentativos)."""
    items = [
        f"{b.get('inicio')} {(b.get('titulo') or 'pendiente').strip()}"
        for b in bloques
        if b.get("inicio")
    ]
    if not items:
        return "Sin bloques agendados todavía. Toca para armar tu día."
    visibles = items[:max_items]
    extra = len(items) - len(visibles)
    cuerpo = " · ".join(visibles)
    if extra > 0:
        cuerpo += f" · +{extra}"
    return cuerpo


def _formatea_pre_actividad(bloque: dict[str, Any], lead_min: int) -> tuple[str, str]:
    """Plantilla de noti pre-actividad. Sin markdown, peruano, sin emojis."""
    titulo_b = (bloque.get("titulo") or "tu siguiente bloque").strip()
    if len(titulo_b) > 50:
        titulo_b = titulo_b[:47] + "…"
    titulo = f"En {lead_min} min: {titulo_b}"
    cuerpo = f"{bloque.get('inicio', '')} · prepara el espacio."
    return titulo, cuerpo


def _formatea_nudge_proximo(bloque: dict[str, Any] | None) -> tuple[str, str]:
    """Nudge del "próximo bloque". Si no queda nada, mensaje neutro."""
    if not bloque:
        return ("Tu día sigue libre", "Si te queda energía, abre Matix y revísalo.")
    titulo_b = (bloque.get("titulo") or "lo siguiente").strip()
    if len(titulo_b) > 50:
        titulo_b = titulo_b[:47] + "…"
    inicio = bloque.get("inicio") or ""
    titulo = f"Lo siguiente: {titulo_b}"
    cuerpo = f"A las {inicio}. Tócame para revisar el día." if inicio else "Tócame para revisar el día."
    return titulo, cuerpo


def _bloque_proximo_a(
    bloques: list[dict[str, Any]], ahora_hhmm: str
) -> dict[str, Any] | None:
    """Primer bloque del día cuyo `inicio` (HH:MM) es ESTRICTAMENTE > `ahora_hhmm`.
    Solo mira bloques con `inicio` (los del plan vienen con inicio/fin/título)."""
    futuros = [
        b for b in bloques
        if (b.get("inicio") or "") > ahora_hhmm
    ]
    if not futuros:
        return None
    return min(futuros, key=lambda b: b.get("inicio") or "99:99")


def _hora_resumen_matutino(
    cfg_nudges: dict[str, Any], despierta_hhmm: str | None
) -> time:
    """Hora local para el resumen matutino: si el usuario marcó despertar HOY,
    la usamos +5 min para que la noti llegue justo cuando ya está despierto;
    si no, fallback `silencio_fin` (default 8:00)."""
    if despierta_hhmm:
        try:
            h, m = despierta_hhmm.split(":")
            base = time(int(h), int(m))
            # +5 min, capado a 23:59
            extra = (base.hour * 60 + base.minute + 5) % (24 * 60)
            return time(extra // 60, extra % 60)
        except (ValueError, AttributeError):
            pass
    fin_silencio = int(cfg_nudges.get("silencio_fin", 8))
    return time(min(23, max(0, fin_silencio)), 0)


# ── Armado principal ─────────────────────────────────────────────────────────


def armar_notis_programadas(
    plan: dict[str, Any],
    cfg_nudges: dict[str, Any] | None,
    *,
    ahora: datetime,
) -> list[NotiProgramada]:
    """Lista determinista de notis programadas para el RESTO de hoy (Lima).

    Reglas:
    - Solo programa notis EN FUTURO respecto a `ahora` (lo que ya pasó se ignora).
    - Nada se programa dentro de quiet hours.
    - El nº de `nudge_proximo` lo limita el dial de intensidad.
    - Cada noti tiene un `dedup_key` estable: `tipo|fecha|HH:MM|ref` — la app
      cancela los anteriores y vuelve a programar; misma `dedup_key` == misma
      ranura, así re-pedir no duplica.

    Args:
        plan: salida de `horario.plan_de_hoy_data(db, ahora=ahora)`.
        cfg_nudges: fila de `config_nudges` (o None si no existe).
        ahora: datetime aware (UTC); el armado lo convierte a Lima.

    Returns:
        Lista ordenada cronológicamente por `disparar_en`.
    """
    cfg = cfg_nudges or {}
    fuera = []  # set de notis a devolver
    dial = str(cfg.get("intensidad") or "intenso")
    lead_min = int(cfg.get("pre_actividad_min") or LEAD_DEFAULT_MIN)
    if lead_min < 0 or lead_min > 120:
        lead_min = LEAD_DEFAULT_MIN

    local_ahora = ahora.astimezone(LIMA)
    fecha = local_ahora.date()
    fecha_iso = fecha.isoformat()
    bloques = list(plan.get("bloques") or [])

    # 1) Resumen matutino — solo si la hora elegida está EN EL FUTURO. Si ya
    # pasó, no rompemos nada; la app puede mostrar el resumen al despertar
    # como una noti instantánea aparte (no programada).
    hora_resumen = _hora_resumen_matutino(cfg, plan.get("despierta"))
    cuando_resumen = datetime(
        fecha.year, fecha.month, fecha.day,
        hora_resumen.hour, hora_resumen.minute, tzinfo=LIMA,
    )
    # El resumen matutino IGNORA quiet hours cuando se ancla al despertar marcado:
    # el usuario ya está despierto, no estaríamos despertándolo. Solo cuando
    # caemos al fallback `silencio_fin` respetamos el silencio (poco probable
    # que falle, pero defensivo).
    anclado_a_despertar = bool(plan.get("despierta"))
    if cuando_resumen > local_ahora and (
        anclado_a_despertar or not _en_silencio_dt(cuando_resumen, cfg)
    ):
        cuerpo = _formatea_resumen(bloques)
        fuera.append(NotiProgramada(
            tipo="resumen_matutino",
            dedup_key=f"resumen_matutino|{fecha_iso}",
            disparar_en=cuando_resumen.astimezone(LIMA),
            titulo="Tu día",
            cuerpo=cuerpo,
            payload="abrir_tu_dia",
        ))

    # 2) Pre-actividad — `lead_min` antes de cada bloque del plan. Solo a
    # futuro (las pasadas ya no se programan) y solo fuera de silencio.
    for b in bloques:
        inicio = b.get("inicio")
        if not isinstance(inicio, str):
            continue
        try:
            h, m = inicio.split(":")
            ini_dt = datetime(fecha.year, fecha.month, fecha.day,
                              int(h), int(m), tzinfo=LIMA)
        except (ValueError, AttributeError):
            continue
        cuando = ini_dt - timedelta(minutes=lead_min)
        if cuando <= local_ahora:
            continue
        if _en_silencio_dt(cuando, cfg):
            continue
        titulo, cuerpo = _formatea_pre_actividad(b, lead_min)
        # Ref del dedup: el set_item / tarea / nodo / titulo si nada de eso
        # hay (un fijo: clase, evento) → titulo normalizado.
        ref = (
            str(b.get("set_item_id") or b.get("tarea_id") or b.get("nodo_id")
                or _slug_corto(b.get("titulo")) or "x")
        )
        fuera.append(NotiProgramada(
            tipo="pre_actividad",
            dedup_key=f"pre_actividad|{fecha_iso}|{inicio}|{ref}",
            disparar_en=cuando,
            titulo=titulo,
            cuerpo=cuerpo,
            payload="abrir_tu_dia",
        ))

    # 3) Nudge "próximo bloque" — repartidos a las horas de `HORARIO_NUDGES`
    # tomando solo `NUDGES_PROXIMO_POR_DIAL[dial]` de ellos a futuro. En cada
    # hora elegida, el cuerpo cita el siguiente bloque pendiente a esa hora.
    n_max = NUDGES_PROXIMO_POR_DIAL.get(dial, 3)
    horas_validas: list[int] = []
    for h in HORARIO_NUDGES:
        cuando_n = datetime(fecha.year, fecha.month, fecha.day, h, 0, tzinfo=LIMA)
        if cuando_n <= local_ahora:
            continue
        if _en_silencio_dt(cuando_n, cfg):
            continue
        horas_validas.append(h)
    horas_validas = horas_validas[:n_max]

    for h in horas_validas:
        cuando_n = datetime(fecha.year, fecha.month, fecha.day, h, 0, tzinfo=LIMA)
        hhmm = f"{h:02d}:00"
        proximo = _bloque_proximo_a(bloques, hhmm)
        # Si no hay próximo a esa hora, igual mandamos el nudge neutro: el
        # usuario sabe que sigue libre (a veces es lo que necesita: respiro).
        titulo, cuerpo = _formatea_nudge_proximo(proximo)
        fuera.append(NotiProgramada(
            tipo="nudge_proximo",
            dedup_key=f"nudge_proximo|{fecha_iso}|{hhmm}",
            disparar_en=cuando_n,
            titulo=titulo,
            cuerpo=cuerpo,
            payload="abrir_tu_dia",
        ))

    # Devolvemos ordenadas cronológicamente — más fácil para el scheduler local
    # y para los logs.
    fuera.sort(key=lambda n: n.disparar_en)
    return fuera


def _slug_corto(texto: Any) -> str:
    """Slug muy corto para usar como ref en el dedup_key. Solo letras/dígitos
    en minúsculas, hasta 12 chars."""
    if not isinstance(texto, str):
        return ""
    out: list[str] = []
    for ch in texto.lower():
        if ch.isalnum():
            out.append(ch)
        if len(out) >= 12:
            break
    return "".join(out) or "x"
