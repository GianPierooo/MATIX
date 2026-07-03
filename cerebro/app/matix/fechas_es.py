"""Parser de fechas en español (registro peruano), DETERMINISTA y PURO.

Resuelve las expresiones de fecha/hora COMUNES para que un "recuérdame X mañana
3pm" o "crea tarea Y el viernes" NO gasten un turno de LLM. Recibe `ahora` (la
hora local de Lima) inyectada — no lee el reloj —, así es trivial de testear.

REGLA INNEGOCIABLE: si NO está seguro, devuelve `None` y el chat delega en el
LLM. NUNCA adivina. Una fecha mal parseada rompe lo único que Matix promete
(que las cosas vuelvan al usuario a tiempo). Por eso los casos ambiguos
(«a las 3» sin am/pm ni franja, «más tarde», «el finde») se delegan.

Lima es UTC-5 fijo (sin horario de verano), así que la aritmética de fechas es
directa. Las franjas por defecto: mañana 09:00 · mediodía 12:00 · tarde 15:00 ·
noche 20:00.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime, time, timedelta


@dataclass(frozen=True)
class ResultadoFecha:
    """Una fecha resuelta con alta confianza + el texto sin la expresión de
    fecha (para usar como título de la tarea)."""

    dt: datetime
    texto_limpio: str


# Normalización que PRESERVA la longitud (para mapear spans al texto original):
# solo baja a minúsculas y quita tildes 1:1. No usa NFD (que cambia longitudes).
_TRANS = str.maketrans("áéíóúüñ", "aeiouun")


def _norm(s: str) -> str:
    return s.lower().translate(_TRANS)


# ── Delegación: ambigüedad y recurrencia → None (al LLM) ─────────────────────

_AMBIGUO = re.compile(
    r"\b(mas tarde|mas adelante|mas noche|luego|al rato|en un rato|un rato|"
    r"pronto|ahorita|mas rato|temprano|la proxima|proxima semana|esta semana|"
    r"la semana que viene|el finde|fin de semana|cuando pueda|algun dia|"
    r"algun rato|un dia de estos|en la madrugada)\b"
)
_RECURRENTE = re.compile(
    r"\b(todos los|todas las|cada|a diario|diariamente|diario|diaria|"
    r"semanal|semanalmente|mensual|mensualmente)\b"
)

_DIAS = {
    "lunes": 0, "martes": 1, "miercoles": 2, "jueves": 3,
    "viernes": 4, "sabado": 5, "domingo": 6,
}
_MESES = {
    "enero": 1, "febrero": 2, "marzo": 3, "abril": 4, "mayo": 5, "junio": 6,
    "julio": 7, "agosto": 8, "septiembre": 9, "setiembre": 9, "octubre": 10,
    "noviembre": 11, "diciembre": 12,
}
_FRANJAS = {"manana": (9, 0), "tarde": (15, 0), "noche": (20, 0)}

# Cualquier CUE temporal (incl. ambiguos): sirve para que el llamador sepa que
# «había intención de fecha» aunque `parsear` devolviera None (ambigua) y así
# delegue al LLM en vez de crear una tarea con la fecha metida en el título.
_CUE_FECHA = re.compile(
    r"\b(hoy|ayer|manana|lunes|martes|miercoles|jueves|viernes|sabado|domingo|"
    r"mediodia|medio dia)\b"
    r"|\ben\s+\d{1,2}\s+(?:dias?|semanas?)\b"
    r"|\bel\s+\d{1,2}\b"
    r"|\b\d{1,2}\s+de\s+(?:" + "|".join(_MESES) + r")\b"
    r"|\b(?:en|por|esta|este)\s+(?:la\s+)?(?:manana|tarde|noche)\b"
    r"|\ba\s+la?s?\s+\d{1,2}\b"
    r"|\b\d{1,2}(?::\d{2})?\s*[ap]\.?\s?m\.?\b"
    r"|\b\d{1,2}:\d{2}\b"
)


def hay_senal_de_fecha(texto: str) -> bool:
    """True si el texto tiene CUALQUIER cue temporal (incluidos los ambiguos y
    recurrentes). Úsalo cuando `parsear` devolvió None para decidir si delegar
    al LLM (había intención de fecha) o seguir sin fecha."""
    norm = _norm(texto)
    return bool(
        _CUE_FECHA.search(norm) or _AMBIGUO.search(norm) or _RECURRENTE.search(norm)
    )


_DIAS_SEMANA_RE = r"\b(lunes|martes|miercoles|jueves|viernes|sabado|domingo)\b"
_RELATIVOS_RE = r"\b(hoy|ayer|manana)\b"
_MERIDIANO_RE = r"\b\d{1,2}(?::\d{2})?\s*[ap]\.?\s?m\.?\b"
_EL_N_RE = r"\bel\s+\d{1,2}\b"
_DISYUNCION_RE = re.compile(r"\b[ou]\b|/")


def _es_multiple(norm: str) -> bool:
    """True si el texto tiene DOS o más fechas/horas (disyunción o lista): "el
    lunes o el martes", "a las 3pm y a las 5pm", "hoy o mañana". Ahí NO se puede
    elegir sin adivinar → se delega al LLM. Es el guard anti-adivinanza."""
    # Quita las FRANJAS ("en la mañana", "por la tarde", "esta noche") para que su
    # palabra ("mañana") no cuente como una SEGUNDA fecha: "mañana en la mañana"
    # es UNA sola fecha (mañana 09:00), no dos.
    limpio = re.sub(
        r"\b(?:en|por|esta|este)\s+(?:la\s+)?(?:manana|tarde|noche)\b", " ", norm
    )
    # 2+ del MISMO tipo → dos fechas/horas listadas.
    for pat in (_RELATIVOS_RE, _DIAS_SEMANA_RE, _MERIDIANO_RE, _EL_N_RE):
        if len(re.findall(pat, limpio)) > 1:
            return True
    # Disyunción explícita ("A o B", "A / B") junto a cualquier cue temporal.
    if _DISYUNCION_RE.search(limpio) and (_CUE_FECHA.search(limpio) or _AMBIGUO.search(limpio)):
        return True
    # Cross-type: un relativo Y un día de semana = dos anclas de fecha distintas.
    if re.search(_RELATIVOS_RE, limpio) and re.search(_DIAS_SEMANA_RE, limpio):
        return True
    return False


def parsear(texto: str, ahora: datetime) -> ResultadoFecha | None:
    """Devuelve una `ResultadoFecha` si el texto tiene una fecha/hora de ALTA
    confianza; `None` si no hay fecha o es ambigua (→ el LLM decide)."""
    if not texto or not texto.strip():
        return None
    norm = _norm(texto)

    # 1) Recurrencia o ambigüedad → siempre al LLM (no es una fecha puntual).
    if _RECURRENTE.search(norm) or _AMBIGUO.search(norm):
        return None

    # 1b) DOS o más fechas/horas → ambiguo, al LLM. NUNCA tomamos la primera en
    #     silencio (era un bug: "el lunes o el martes" resolvía a lunes).
    if _es_multiple(norm):
        return None

    spans: list[tuple[int, int]] = []

    # 2) Componente de FECHA (día).
    fecha, span_fecha = _parse_fecha(norm, ahora)
    if span_fecha:
        spans.append(span_fecha)

    # 3) Componente de HORA.
    hora, span_hora, hora_ambigua = _parse_hora(norm)
    if hora_ambigua:
        return None  # p. ej. «a las 3» sin am/pm ni franja → delega
    if span_hora:
        spans.append(span_hora)

    if fecha is None and hora is None:
        return None  # no hay ninguna señal de fecha

    base = fecha if fecha is not None else ahora.date()
    if hora is not None:
        dt = datetime.combine(base, time(hora[0], hora[1]), tzinfo=ahora.tzinfo)
    else:
        # Solo fecha, sin hora → default de la mañana (09:00).
        dt = datetime.combine(base, time(9, 0), tzinfo=ahora.tzinfo)

    # Solo hora (sin día): si ya pasó hoy, es para mañana (convención común).
    if fecha is None and dt <= ahora:
        dt = dt + timedelta(days=1)

    # Guard: NUNCA una fecha en el pasado. Ante eso, delega (no adivina).
    if dt <= ahora:
        return None

    return ResultadoFecha(dt=dt, texto_limpio=_quitar_spans(texto, spans))


# ── Fecha (día) ──────────────────────────────────────────────────────────────


def _parse_fecha(norm: str, ahora: datetime):
    """Devuelve (date | None, span | None). Primer patrón que aplica gana."""
    hoy = ahora.date()

    m = re.search(r"\bpasado\s+manana\b", norm)
    if m:
        return hoy + timedelta(days=2), m.span()

    m = re.search(r"\bmanana\b", norm)
    if m:
        return hoy + timedelta(days=1), m.span()

    m = re.search(r"\bhoy\b", norm)
    if m:
        return hoy, m.span()

    # "en N dias" / "en N semanas".
    m = re.search(r"\ben\s+(\d{1,2})\s+(dias?|semanas?)\b", norm)
    if m:
        n = int(m.group(1))
        dias = n * 7 if m.group(2).startswith("semana") else n
        return hoy + timedelta(days=dias), m.span()

    # "el 15 de agosto" / "15 de agosto" (mes explícito).
    m = re.search(r"\b(?:el\s+)?(\d{1,2})\s+de\s+([a-z]+)\b", norm)
    if m and m.group(2) in _MESES:
        dia, mes = int(m.group(1)), _MESES[m.group(2)]
        f = _fecha_valida(ahora.year, mes, dia)
        if f is None:
            return None, None
        if f < hoy:  # ya pasó este año → el próximo
            f = _fecha_valida(ahora.year + 1, mes, dia)
        return f, m.span()

    # Día de semana: "el viernes" / "este viernes" / "viernes" / "proximo viernes".
    m = re.search(
        r"\b(?:(este|el|proximo|siguiente)\s+)?"
        r"(lunes|martes|miercoles|jueves|viernes|sabado|domingo)\b",
        norm,
    )
    if m:
        objetivo = _DIAS[m.group(2)]
        skip_hoy = m.group(1) in ("proximo", "siguiente")
        delta = (objetivo - hoy.weekday()) % 7
        if delta == 0 and skip_hoy:
            delta = 7
        return hoy + timedelta(days=delta), m.span()

    # "el 15" (día del mes, sin mes explícito): próxima ocurrencia.
    m = re.search(r"\bel\s+(\d{1,2})\b", norm)
    if m:
        dia = int(m.group(1))
        if not 1 <= dia <= 31:
            return None, None
        if dia >= hoy.day:
            f = _fecha_valida(ahora.year, ahora.month, dia)
        else:
            mes = ahora.month + 1
            anio = ahora.year + (1 if mes > 12 else 0)
            mes = 1 if mes > 12 else mes
            f = _fecha_valida(anio, mes, dia)
        return (f, m.span()) if f else (None, None)

    return None, None


def _fecha_valida(anio: int, mes: int, dia: int):
    from datetime import date
    try:
        return date(anio, mes, dia)
    except ValueError:
        return None


# ── Hora ─────────────────────────────────────────────────────────────────────


def _parse_hora(norm: str):
    """Devuelve (hora | None, span | None, ambigua: bool). `hora` = (h, m) en
    24h. `ambigua=True` cuando el usuario claramente pidió una hora pero no se
    puede desambiguar (am/pm) → el caller delega en el LLM."""
    # 1) Con meridiano: "3pm", "10 am", "10:30pm". La hora con meridiano DEBE ser
    #    1-12 (un "13pm"/"99pm" es basura → no lo tratamos como hora válida).
    m = re.search(r"\b(\d{1,2})(?::(\d{2}))?\s*([ap])\.?\s?m\.?\b", norm)
    if m and 1 <= int(m.group(1)) <= 12:
        h = int(m.group(1)) % 12
        if m.group(3) == "p":
            h += 12
        mm = int(m.group(2) or 0)
        if _hora_ok(h, mm):
            return (h, mm), m.span(), False

    # 2) Con franja explícita: "3 de la tarde", "a las 9 de la manana".
    m = re.search(
        r"\b(?:a\s+la?s?\s+)?(\d{1,2})(?::(\d{2}))?\s+de\s+la\s+"
        r"(manana|tarde|noche|madrugada)\b",
        norm,
    )
    if m:
        h = int(m.group(1)) % 12
        franja = m.group(3)
        if franja in ("tarde", "noche"):
            h += 12
        mm = int(m.group(2) or 0)
        if _hora_ok(h, mm):
            return (h, mm), m.span(), False

    # 3) 24h explícita con minutos: "a las 15:00", "9:30".
    m = re.search(r"\b(?:a\s+la?s?\s+)?(\d{1,2}):(\d{2})\b", norm)
    if m:
        h, mm = int(m.group(1)), int(m.group(2))
        if _hora_ok(h, mm):
            return (h, mm), m.span(), False

    # 4) Franjas del día por defecto. Prefijo claro (en/por/esta/este + "la"
    #    opcional) para NO chocar con la FECHA "mañana": "en la mañana", "por la
    #    tarde", "esta noche". "la" es opcional ("esta noche" no lleva "la").
    m = re.search(r"\b(?:en|por|esta|este)\s+(?:la\s+)?(manana|tarde|noche)\b", norm)
    if m:
        return _FRANJAS[m.group(1)], m.span(), False
    m = re.search(r"\b(al\s+mediodia|mediodia|medio\s+dia)\b", norm)
    if m:
        return (12, 0), m.span(), False

    # 5) AMBIGUO: dijo "a las N" pero sin am/pm ni franja → no adivinamos.
    if re.search(r"\ba\s+la?s?\s+\d{1,2}\b", norm):
        return None, None, True

    return None, None, False


def _hora_ok(h: int, mm: int) -> bool:
    return 0 <= h <= 23 and 0 <= mm <= 59


# ── Limpieza del título ──────────────────────────────────────────────────────


def _quitar_spans(texto: str, spans: list[tuple[int, int]]) -> str:
    """Quita del texto ORIGINAL los tramos de fecha/hora (para el título) y
    limpia conectores y espacios sobrantes. Best-effort: si queda algo, no
    afecta la fecha (que es lo importante)."""
    if not spans:
        return texto.strip()
    out = texto
    for ini, fin in sorted(spans, reverse=True):
        out = out[:ini] + " " + out[fin:]
    out = re.sub(r"\s+", " ", out).strip()
    # Conectores colgantes que quedan al remover la fecha.
    out = re.sub(r"\s+(a\s+las|a\s+la|para\s+el|para\s+la|para|el|de)\s*$", "", out,
                 flags=re.IGNORECASE).strip()
    out = re.sub(r"^\s*(a\s+las|a\s+la|el|para)\s+", "", out,
                 flags=re.IGNORECASE).strip()
    out = out.strip(" ,.-—")
    return out
