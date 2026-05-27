"""Medidor de uso de OpenAI (Capa 2 Paso 5).

Acumula los `usage` que devuelven las respuestas de chat completions y
calcula un costo estimado en USD. Singleton en memoria — al reiniciar
el cerebro vuelve a cero. La franja del chat de Matix lo lee vía
`GET /api/v1/matix/uso`.

Decisión: tracking en memoria, sin persistir. Razones:

- Es información operativa, no del usuario. Si se pierde con un
  reinicio, no pasa nada importante — el usuario sabe que es
  consumo acumulado de la sesión del cerebro, no de su vida entera.
- Persistir suma complejidad (tabla nueva, escrituras en cada
  respuesta) sin beneficio claro en Capa 2.
- Si en el futuro queremos histórico mensual, lo añadimos sin que
  el resto del código cambie: este módulo expone `MedidorUso` con
  una API simple que un store persistente puede reemplazar.

Precios: se editan acá como constantes del archivo. Si OpenAI los
cambia o se usa otro modelo, se ajustan estos valores y el resto
del código sigue igual.
"""
from __future__ import annotations

from dataclasses import dataclass
from threading import Lock
from typing import Any

# ─── Tarifas — actualizar acá cuando OpenAI las mueva ───────────────
# Fuente (2026-05-26): https://openai.com/api/pricing/
# gpt-4o-mini · USD por 1 millón de tokens.
_PRECIO_INPUT_POR_M = 0.150
_PRECIO_INPUT_CACHED_POR_M = 0.075  # cached input = mitad de precio
_PRECIO_OUTPUT_POR_M = 0.600

# Whisper · USD por minuto de audio. Lo trackeamos separado porque
# Whisper no devuelve `usage` (cobra por duración del audio).
_PRECIO_WHISPER_POR_MIN = 0.006

# tts-1 · USD por 1M caracteres de input. Cobra por longitud del
# texto leído. (tts-1-hd cuesta el doble; usamos tts-1 por latencia
# y costo en el modo manos libres.)
_PRECIO_TTS_POR_M_CHARS = 15.0


@dataclass
class _Snapshot:
    prompt_tokens: int = 0
    cached_prompt_tokens: int = 0
    completion_tokens: int = 0
    llamadas_chat: int = 0
    segundos_whisper: float = 0.0
    llamadas_whisper: int = 0
    caracteres_tts: int = 0
    llamadas_tts: int = 0


class MedidorUso:
    """Acumulador thread-safe del consumo. Una sola instancia
    (singleton del proceso del cerebro)."""

    def __init__(self) -> None:
        self._s = _Snapshot()
        self._lock = Lock()

    def registrar_chat(self, usage: Any) -> None:
        """Acepta el objeto `usage` de OpenAI (puede ser pydantic-like
        con atributos o un dict). Es tolerante: si falta algún campo,
        no rompe."""
        if usage is None:
            return
        prompt = _get(usage, "prompt_tokens", 0)
        completion = _get(usage, "completion_tokens", 0)
        # Detalle de cached tokens — soportado por gpt-4o-mini cuando
        # el prompt caching aplica.
        cached = 0
        details = _get(usage, "prompt_tokens_details", None)
        if details is not None:
            cached = _get(details, "cached_tokens", 0) or 0
        with self._lock:
            self._s.prompt_tokens += int(prompt or 0)
            self._s.completion_tokens += int(completion or 0)
            self._s.cached_prompt_tokens += int(cached or 0)
            self._s.llamadas_chat += 1

    def registrar_whisper(self, segundos: float) -> None:
        if segundos <= 0:
            return
        with self._lock:
            self._s.segundos_whisper += float(segundos)
            self._s.llamadas_whisper += 1

    def registrar_tts(self, caracteres: int) -> None:
        if caracteres <= 0:
            return
        with self._lock:
            self._s.caracteres_tts += int(caracteres)
            self._s.llamadas_tts += 1

    def snapshot(self) -> dict[str, Any]:
        """Devuelve el estado actual + costo estimado en USD."""
        with self._lock:
            s = _Snapshot(**self._s.__dict__)
        no_cache = max(0, s.prompt_tokens - s.cached_prompt_tokens)
        costo = (
            no_cache * _PRECIO_INPUT_POR_M / 1_000_000
            + s.cached_prompt_tokens * _PRECIO_INPUT_CACHED_POR_M / 1_000_000
            + s.completion_tokens * _PRECIO_OUTPUT_POR_M / 1_000_000
            + (s.segundos_whisper / 60.0) * _PRECIO_WHISPER_POR_MIN
            + s.caracteres_tts * _PRECIO_TTS_POR_M_CHARS / 1_000_000
        )
        return {
            "prompt_tokens": s.prompt_tokens,
            "cached_prompt_tokens": s.cached_prompt_tokens,
            "completion_tokens": s.completion_tokens,
            "total_tokens": s.prompt_tokens + s.completion_tokens,
            "llamadas_chat": s.llamadas_chat,
            "segundos_whisper": round(s.segundos_whisper, 1),
            "llamadas_whisper": s.llamadas_whisper,
            "caracteres_tts": s.caracteres_tts,
            "llamadas_tts": s.llamadas_tts,
            "costo_usd": round(costo, 6),
            # Útil para la UI: precios usados para el cálculo.
            "precios": {
                "input_por_m_usd": _PRECIO_INPUT_POR_M,
                "input_cached_por_m_usd": _PRECIO_INPUT_CACHED_POR_M,
                "output_por_m_usd": _PRECIO_OUTPUT_POR_M,
                "whisper_por_min_usd": _PRECIO_WHISPER_POR_MIN,
                "tts_por_m_chars_usd": _PRECIO_TTS_POR_M_CHARS,
            },
        }

    def reiniciar(self) -> None:
        """Borra el contador. Útil para tests o si el usuario quiere
        resetear desde Ajustes en el futuro."""
        with self._lock:
            self._s = _Snapshot()


def _get(obj: Any, attr: str, default: Any) -> Any:
    """Lee `attr` de `obj` independientemente de si es dict o un
    objeto con atributos. `pydantic` v2 expone ambos."""
    if obj is None:
        return default
    if isinstance(obj, dict):
        return obj.get(attr, default)
    return getattr(obj, attr, default)


# Singleton del proceso. Importable directamente.
medidor = MedidorUso()
