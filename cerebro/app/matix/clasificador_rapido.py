"""Clasificador de intención rápido — PRE-LLM.

Para los casos LIMPIOS y SIN AMBIGÜEDAD, en vez de pagar la latencia de OpenAI/
Anthropic+tools, ejecutamos la acción directo desde reglas:

- "anota X" / "apunta X" / "guarda esto: X" → `crear_apunte(titulo=X)`.
- "crea/agrega/añade tarea X" SIN fecha → `crear_tarea(titulo=X)`.
- Saludos y conversaciones triviales que no piden nada ("hola", "gracias",
  "ok") → respuesta plantilla, sin LLM.

QUÉ NO HACE este clasificador:
- Fechas relativas ("mañana", "el viernes 10am"). Esa resolución la deja al LLM
  (que ya tiene `crear_tarea` con `vence_en`). Aceptarlas acá implicaría un
  parser de fechas-en-español decente; el riesgo de equivocarse > la ganancia.
- Acciones con id (marcar/posponer/borrar tarea por nombre). Necesita resolver
  qué tarea es ("la de comprar pan, no la de pan integral") → al LLM.
- Texto ambiguo (sin verbo claro, mensaje de varios temas, preguntas). Cae al LLM.

Diseño defensivo: ante la MÍNIMA duda, devolvemos `None` y el chat sigue su
camino normal. Falsos positivos serían lo peor: el usuario pide "anota: cita con
juan mañana 10am" y guardamos "cita con juan mañana 10am" como apunte sin
recordatorio. Por eso este módulo es CONSERVADOR.

Es PURO (sin BD, sin red, sin reloj): recibe el texto del usuario y devuelve
una `IntencionRapida | None`. Trivial de testear.
"""
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Literal

from . import fechas_es


@dataclass(frozen=True)
class IntencionRapida:
    """Lo que el chat tiene que ejecutar SIN LLM.

    - `tipo` "tool" → llamar a `ejecutar_tool(db, nombre, args)`. El chat
      arma la respuesta corta con plantilla (ya tiene los datos).
    - `tipo` "saludo" → no toca BD, solo responde el `mensaje` directo.

    `etiqueta_motivo` viaja al log de latencia para saber qué disparó la ruta
    rápida (útil para ajustar el clasificador con datos reales).
    """

    tipo: Literal["tool", "saludo"]
    nombre: str | None = None        # nombre de la tool (si tipo="tool")
    args: dict[str, Any] | None = None
    mensaje: str | None = None       # respuesta lista (si tipo="saludo")
    etiqueta_motivo: str = ""        # "saludo" | "anota" | "crea_tarea_simple"


# ── Normalización ────────────────────────────────────────────────────────────


def _norm(texto: str) -> str:
    """Minúsculas + sin acentos. Robusto a tildes pero CONSERVA puntuación: la
    coma o los dos puntos son señal de "anota: lo que sigue es el contenido"."""
    s = (texto or "").lower().strip()
    s = unicodedata.normalize("NFD", s)
    return "".join(c for c in s if unicodedata.category(c) != "Mn")


# ── Saludos / conversación trivial ───────────────────────────────────────────
#
# Mensajes ULTRA cortos sin ningún verbo de acción. La respuesta debe ser cálida
# y peruana (sin voseo) — Matix tiene personalidad, no es un autoresponder. Si
# el mensaje trae cualquier verbo o más de N palabras, dejamos pasar al LLM.

_SALUDOS = {
    "hola": "¡Hola, Gian Piero! ¿En qué te ayudo?",
    "buenas": "¡Buenas! ¿Qué necesitas?",
    "buenos dias": "¡Buenos días! ¿Por dónde arrancamos?",
    "buenas tardes": "¡Buenas tardes! ¿Qué necesitas?",
    "buenas noches": "¡Buenas noches! ¿Qué necesitas?",
    "hey": "¡Hey! Cuéntame.",
    "ey": "¡Ey! Cuéntame.",
    "ola": "¡Hola! ¿Qué necesitas?",
}

_AGRADECIMIENTOS = {
    "gracias",
    "muchas gracias",
    "mil gracias",
    "buenisimo",
    "buenazo",
    "perfecto",
    "ok gracias",
    "ok, gracias",
}

_AFIRMACIONES_VACIAS = {
    "ok",
    "okey",
    "ya",
    "dale",
    "listo",
    "bacan",
    "chevere",
    "genial",
    "si",
    "no",
}


def _detectar_saludo(texto_norm: str) -> IntencionRapida | None:
    """Saludo / agradecimiento / afirmación sin contenido. Texto MUY corto y
    que coincide EXACTO con uno de los sets. Cualquier extra (verbo, número,
    pregunta) → None, lo maneja el LLM."""
    # Limpieza ligera al borde — quitamos signos y comillas, dejamos el core.
    nucleo = texto_norm.strip(" .!?¡¿\"'·-—\n\t")
    if not nucleo or len(nucleo) > 32:
        return None
    if nucleo in _SALUDOS:
        return IntencionRapida(
            tipo="saludo", mensaje=_SALUDOS[nucleo], etiqueta_motivo="saludo"
        )
    if nucleo in _AGRADECIMIENTOS:
        return IntencionRapida(
            tipo="saludo",
            mensaje="¡De nada! Cualquier cosa, acá estoy.",
            etiqueta_motivo="agradecimiento",
        )
    if nucleo in _AFIRMACIONES_VACIAS:
        # Afirmación suelta sin contexto: respuesta neutra (no inventamos
        # acción). El usuario probablemente está cerrando un hilo.
        return IntencionRapida(
            tipo="saludo",
            mensaje="Va.",
            etiqueta_motivo="afirmacion",
        )
    return None


# ── "Anota X" → crear_apunte ─────────────────────────────────────────────────
#
# Patrones LIMPIOS donde el resto del mensaje ES el contenido del apunte. NO
# detectamos "anota llamar a juan" como tarea — el usuario eligió "anota", no
# "agenda" ni "recuérdame". El apunte es lo más seguro: no pierde nada y el
# usuario lo puede convertir a tarea con un toque.
#
# Forma: "anota[:|,] <contenido>" / "apunta…" / "guarda esto: …" / "toma nota…"
# El verbo debe estar al INICIO. Si el usuario dice "no anotes esto", no
# disparamos (el "no" delante del verbo).

# Clases de letra tilde-tolerantes (a/á, e/é, etc., n/ñ). Permiten que los
# regex acepten el texto ORIGINAL (con o sin tildes) sin tener que normalizar
# primero — así el `group(1)` (el contenido) preserva las tildes del usuario.
_LA, _LE, _LI, _LU, _LN = "[aá]", "[eé]", "[ií]", "[uú]", "[nñ]"

_RE_ANOTA = re.compile(
    rf"^(?:anot{_LA}(?:me)?|ap{_LU}nt{_LA}(?:me)?|toma\s+nota(?:\s+de)?|"
    rf"guarda\s+(?:esto|esta\s+idea)|nota(?:\s+r{_LA}pida)?)"
    rf"\s*[:,\-]?\s+(.+)$",
    re.IGNORECASE | re.DOTALL,
)

# Verbos que SI están en el contenido VETAN el camino rápido: el usuario quería
# una tarea ("anota llamar al banco mañana") o un evento, no un apunte plano.
# Lo dejamos al LLM, que decide bien.
_VERBOS_DE_ACCION = re.compile(
    r"\b(llamar|pagar|comprar|enviar|mandar|terminar|entregar|estudiar|leer|"
    r"revisar|hacer|completar|escribir|preparar|presentar|recoger|sacar)\b",
    re.IGNORECASE,
)

# Marcadores de fecha que VETAN: "anota cita mañana 10am" debe ir al LLM para
# que cree una tarea/evento con `vence_en`, no un apunte sin fecha. Las palabras
# clave aparecen sin tilde (ya normalizamos), pero también las dejamos con
# tilde por si alguna ruta llega sin normalizar.
_MARCADORES_FECHA = re.compile(
    r"\b(hoy|manana|tarde|noche|ayer|lunes|martes|miercoles|jueves|viernes|"
    r"sabado|domingo|enero|febrero|marzo|abril|mayo|junio|julio|agosto|"
    r"septiembre|octubre|noviembre|diciembre|a\.m\.|p\.m\.)\b"
    # "10am" / "10 am" / "10pm": el \b no funciona entre dígito y letra, por
    # eso pedimos explícito dígito+(am|pm).
    r"|\d{1,2}\s*(?:am|pm)\b"
    r"|\b\d{1,2}\s*(?::|h)\s*\d{0,2}\b"
    r"|\bel\s+\d{1,2}\b",
    re.IGNORECASE,
)


def _detectar_anota(texto_original: str, texto_norm: str) -> IntencionRapida | None:
    """Captura "anota: <contenido>" como apunte directo. Usa el texto ORIGINAL
    (con tildes y mayúsculas) para el título del apunte; el normalizado solo
    para los regex de veto.

    Veta: contenido vacío, demasiado largo (>200 chars: probablemente texto
    para procesar, no un apunte), verbos de acción o marcadores de fecha.
    """
    m = _RE_ANOTA.match(texto_original.strip())
    if not m:
        return None
    contenido = m.group(1).strip()
    if not contenido or len(contenido) > 200:
        return None
    # Veto por verbo de acción o fecha: ahí el usuario quería una tarea,
    # no un apunte. Al LLM.
    contenido_norm = _norm(contenido)
    if _VERBOS_DE_ACCION.search(contenido_norm):
        return None
    if _MARCADORES_FECHA.search(contenido_norm):
        return None
    # Título: la primera oración o frase, hasta 80 chars (igual que el resto
    # del proyecto). El "contenido" se duplica en `contenido` por completitud
    # (la tool soporta ambos).
    titulo = _primer_renglon(contenido, max_chars=80)
    return IntencionRapida(
        tipo="tool",
        nombre="crear_apunte",
        args={"titulo": titulo},
        etiqueta_motivo="anota",
    )


def _primer_renglon(texto: str, *, max_chars: int) -> str:
    """Primera oración del texto, capada a `max_chars`. Útil para el título."""
    # Cortamos en signo de puntuación fuerte o salto de línea.
    candidato = re.split(r"[.!?\n]", texto, maxsplit=1)[0].strip()
    if not candidato:
        candidato = texto.strip()
    if len(candidato) > max_chars:
        candidato = candidato[:max_chars].rstrip() + "…"
    return candidato


# ── "Crea tarea X" simple (sin fecha) → crear_tarea ──────────────────────────
#
# El verbo va al inicio + un titular concreto + NADA más. Si trae fecha o
# tiene varias oraciones, al LLM.

_RE_CREA_TAREA = re.compile(
    rf"^(?:cr{_LE}a(?:me)?|agrega(?:me)?|a{_LN}ade(?:me)?|pon(?:me)?|nueva|"
    rf"agend{_LA}me|agenda)\s+(?:una\s+)?(?:tarea|pendiente|tarea\s+nueva)"
    rf"\s*[:,\-]?\s+(.+)$",
    re.IGNORECASE | re.DOTALL,
)

# "recuérdame X" típico: si el usuario quería recordatorio con fecha, los
# marcadores de fecha lo vetan. Sin fecha, "recuérdame comprar pan" → tarea
# sin vencimiento; es seguro.
_RE_RECUERDAME = re.compile(
    rf"^recu{_LE}rda(?:me)?\s+(?:que\s+)?(.+)$",
    re.IGNORECASE | re.DOTALL,
)


def _detectar_crear_tarea(
    texto_original: str, texto_norm: str, ahora: datetime | None = None
) -> IntencionRapida | None:
    """Captura "crea tarea: X" / "agrega una tarea X" / "recuérdame X".

    Con `ahora` (hora de Lima), resuelve las fechas comunes de forma
    DETERMINISTA (`fechas_es`) y setea `vence_en` — así "recuérdame X mañana
    3pm" no gasta un turno de LLM. Si el parser NO está seguro (fecha ambigua),
    DELEGA al LLM (nunca adivina). Sin `ahora` (compat), veta si hay fecha.

    Veta: contenido muy largo o vacío.
    """
    texto = texto_original.strip()
    m = _RE_CREA_TAREA.match(texto) or _RE_RECUERDAME.match(texto)
    if not m:
        return None
    contenido = m.group(1).strip()
    if not contenido or len(contenido) > 160:
        return None
    contenido_norm = _norm(contenido)

    vence_en: str | None = None
    titulo_fuente = contenido
    if ahora is not None:
        r = fechas_es.parsear(contenido, ahora)
        if r is not None:
            vence_en = r.dt.isoformat()
            titulo_fuente = r.texto_limpio or contenido
        elif fechas_es.hay_senal_de_fecha(contenido):
            # Había intención de fecha pero el parser no está seguro → al LLM
            # (p. ej. "a las 3" sin am/pm, "más tarde", "cada lunes").
            return None
    elif _MARCADORES_FECHA.search(contenido_norm):
        # Sin reloj inyectado no resolvemos fechas: comportamiento clásico.
        return None

    titulo = _primer_renglon(titulo_fuente, max_chars=80)
    # Quitamos artículos de inicio ("a comprar pan" → "comprar pan").
    titulo = re.sub(r"^(?:que\s+|de\s+|a\s+)", "", titulo, flags=re.IGNORECASE).strip()
    if not titulo:
        return None
    args: dict[str, Any] = {"titulo": titulo}
    if vence_en:
        args["vence_en"] = vence_en
    return IntencionRapida(
        tipo="tool",
        nombre="crear_tarea",
        args=args,
        etiqueta_motivo="crea_tarea_fecha" if vence_en else "crea_tarea_simple",
    )


# ── API pública ──────────────────────────────────────────────────────────────


def detectar(
    mensaje: str,
    *,
    hay_imagen: bool = False,
    hay_documento: bool = False,
    modo_activo: str | None = None,
    ahora: datetime | None = None,
) -> IntencionRapida | None:
    """Devuelve una intención rápida si el mensaje encaja LIMPIO en uno de los
    patrones, o `None` si debe ir al LLM.

    Vetos transversales (NUNCA ruta rápida):
    - Hay imagen o documento adjunto → el modelo tiene que mirarlos.
    - Modo "pesado" activo (tesis, estudio) → el usuario está en sesión de
      trabajo a fondo; respetar el contexto del modo es más valioso que
      ahorrar 1s en un saludo.
    - Mensaje vacío.
    """
    if not mensaje or not mensaje.strip():
        return None
    if hay_imagen or hay_documento:
        return None
    if modo_activo in ("tesis", "estudio"):
        return None
    texto_original = mensaje.strip()
    texto_norm = _norm(texto_original)

    # 1) Saludo / agradecimiento (más barato: comparación exacta contra sets).
    saludo = _detectar_saludo(texto_norm)
    if saludo:
        return saludo

    # 2) "Anota X" → crear_apunte (caso muy común y barato de extraer).
    anota = _detectar_anota(texto_original, texto_norm)
    if anota:
        return anota

    # 3) "Crea tarea X" → crear_tarea. Con `ahora`, resuelve fechas comunes de
    #    forma determinista (sin LLM); si la fecha es ambigua, delega al LLM.
    crear = _detectar_crear_tarea(texto_original, texto_norm, ahora=ahora)
    if crear:
        return crear

    return None
