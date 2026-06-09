"""Motor de recurrencia ÚNICO del hub (2.0 · Fase 3).

UNA sola fuente de verdad para "esto se repite". Antes la expansión de
recurrencia vivía en `matix/horario.ocurre_en` (eventos) y la recurrencia de
clases se materializaba aparte en Universidad sin compartir nada. Aquí se
unifica: tanto los EVENTOS recurrentes (regla en la tabla `eventos`) como las
SESIONES DE CLASE (filas semanales en `sesiones_clase`) resuelven "¿cae en esta
fecha?" por las MISMAS funciones de este módulo.

Convenciones de día de la semana (cuidado, conviven dos en la BD):
  - Eventos (`recurrencia_dias_semana`): ISO, 1=lunes … 7=domingo
    (es lo que devuelve `date.isoweekday()`).
  - Sesiones de clase (`dia_semana`): índice 0=lunes … 6=domingo
    (es lo que devuelve `date.weekday()`).
`iso_de_indice` convierte 0–6 → 1–7 para que AMBOS midan el día con la misma
vara (`isoweekday`). Así no hay dos lógicas de "qué día se repite".

PURO: sin BD, sin red. Trivial de testear.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo

LIMA = ZoneInfo("America/Lima")

# Vocabulario de la regla (lo valida el comando antes de persistir).
FREQS = ("diaria", "semanal", "mensual")
FIN_TIPOS = ("nunca", "hasta", "conteo")


# ── Parseo de fechas (copias locales para no acoplar a horario) ──────────────


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


# ── Día de la semana: un solo modelo ─────────────────────────────────────────


def iso_de_indice(indice: int) -> int:
    """Índice 0=lunes…6=domingo → ISO 1=lunes…7=domingo."""
    return int(indice) + 1


def indice_de_iso(iso: int) -> int:
    """ISO 1=lunes…7=domingo → índice 0=lunes…6=domingo."""
    return int(iso) - 1


def es_indice_valido(d: Any) -> bool:
    """¿`d` es un índice de día 0–6 (modelo de sesiones_clase)?"""
    try:
        return 0 <= int(d) <= 6
    except (ValueError, TypeError):
        return False


def sesion_ocurre_en(dia_semana_0a6: int, fecha: date) -> bool:
    """¿Una sesión de clase (dia_semana 0–6) cae en `fecha`? Usa la MISMA vara
    que los eventos semanales (`isoweekday`). Esta es la unificación: la
    recurrencia de clases y la de eventos comparten este criterio."""
    return iso_de_indice(dia_semana_0a6) == fecha.isoweekday()


# ── Expansión de la recurrencia de un EVENTO ─────────────────────────────────


def _ordinal_ocurrencia(freq: str, dias_semana: Any, inicio: date, fecha: date) -> int:
    """Número de ocurrencia (1-based) de `fecha` desde `inicio` para evaluar el
    fin por conteo. PURO."""
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


def es_recurrente(evento: dict[str, Any]) -> bool:
    return bool((evento.get("recurrencia_freq") or "").strip())


def ocurre_en(evento: dict[str, Any], fecha: date) -> bool:
    """¿Este evento cae en `fecha`? Maneja eventos sueltos y recurrentes
    (diaria/semanal/mensual) con su fin (nunca/hasta/conteo) y las EXCEPCIONES
    (`recurrencia_excepciones`: fechas detachadas/borradas con alcance
    "solo_esta"). PURO.

    Expande la recurrencia que en la BD vive solo como REGLA (no materializada).
    Es el motor único: lo usa `horario`, `asistencia_eventos`, el comando de
    eventos y la consulta de calendario."""
    ini = _parse_dt(evento.get("inicia_en"))
    if ini is None:
        return False
    ini_d = ini.astimezone(LIMA).date()
    freq = (evento.get("recurrencia_freq") or "").strip().lower()
    if not freq:
        return ini_d == fecha
    if fecha < ini_d:
        return False
    # Excepción: esta fecha fue borrada/detachada de la serie.
    if fecha in _excepciones(evento):
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
            if _ordinal_ocurrencia(
                freq, evento.get("recurrencia_dias_semana"), ini_d, fecha
            ) > int(conteo):
                return False
    return True


def _excepciones(evento: dict[str, Any]) -> set[date]:
    out: set[date] = set()
    for raw in evento.get("recurrencia_excepciones") or ():
        d = _parse_date(raw)
        if d is not None:
            out.add(d)
    return out


def ocurrencias_en_rango(
    evento: dict[str, Any], desde: date, hasta: date, *, tope: int = 366
) -> list[date]:
    """Lista las fechas concretas en que `evento` ocurre dentro de [desde, hasta]
    (inclusive). Para un evento suelto es 0 o 1 fecha. `tope` acota el barrido."""
    if hasta < desde:
        desde, hasta = hasta, desde
    out: list[date] = []
    d = desde
    pasos = 0
    while d <= hasta and pasos < tope:
        if ocurre_en(evento, d):
            out.append(d)
        d = d + timedelta(days=1)
        pasos += 1
    return out
