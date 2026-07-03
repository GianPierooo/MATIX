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

import contextvars
import logging
from contextlib import contextmanager
from dataclasses import dataclass, field
from threading import Lock
from typing import Any

logger = logging.getLogger("matix.uso")

# Operación en curso para la telemetría por-operación. La fija la capa pública
# (chat por defecto; visión/extracción/repaso la marcan al llamar al modelo).
# Los registradores la leen para etiquetar cada llamada. Es un ContextVar → cada
# request/task tiene su copia, así que es seguro con concurrencia.
operacion_ctx: contextvars.ContextVar[str] = contextvars.ContextVar(
    "matix_llm_operacion", default="chat"
)


@contextmanager
def operacion(nombre: str):
    """Marca la operación en curso para la telemetría; se restaura al salir."""
    token = operacion_ctx.set(nombre)
    try:
        yield
    finally:
        operacion_ctx.reset(token)

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

# text-embedding-3-small · USD por 1M tokens. Es el modelo barato
# y rápido de OpenAI para embeddings (1536 dims). En la práctica
# domina por tokens de input; los apuntes del usuario son del
# orden de cientos a unos miles de tokens cada uno.
_PRECIO_EMBED_POR_M = 0.020

# Tavily (búsqueda web) · USD por búsqueda. Aproximado: el plan tiene un cupo
# gratis mensual; arriba de eso cuesta ~$0.008 por búsqueda. Es un ESTIMADO
# para que el monitoreo de costo dé noción.
_PRECIO_TAVILY_POR_BUSQUEDA = 0.008


@dataclass
class _Snapshot:
    prompt_tokens: int = 0
    cached_prompt_tokens: int = 0
    completion_tokens: int = 0
    # Costo del chat acumulado en USD. Se suma POR REQUEST con el precio del
    # modelo que se usó (puede variar si el usuario cambia de modelo), en vez
    # de recomputarlo al final con un precio fijo.
    costo_chat_usd: float = 0.0
    llamadas_chat: int = 0
    # Desglose por proveedor (observabilidad del failover): cuánto costó y
    # cuántas llamadas sirvió cada proveedor del chat/visión.
    costo_chat_openai_usd: float = 0.0
    costo_chat_anthropic_usd: float = 0.0
    llamadas_chat_openai: int = 0
    llamadas_chat_anthropic: int = 0
    segundos_whisper: float = 0.0
    llamadas_whisper: int = 0
    caracteres_tts: int = 0
    llamadas_tts: int = 0
    tokens_embedding: int = 0
    llamadas_embedding: int = 0
    llamadas_busqueda_web: int = 0
    # Desglose por OPERACIÓN (chat / vision:* / extraccion:* / repaso / embedding
    # / whisper / tts): {op: {llamadas, tokens_in, tokens_out, cached, costo_usd}}.
    por_operacion: dict[str, dict[str, float]] = field(default_factory=dict)


class MedidorUso:
    """Acumulador thread-safe del consumo. Una sola instancia
    (singleton del proceso del cerebro)."""

    def __init__(self) -> None:
        self._s = _Snapshot()
        self._lock = Lock()

    def registrar_chat(
        self,
        usage: Any,
        *,
        precio_input_por_m: float | None = None,
        precio_output_por_m: float | None = None,
        precio_cached_por_m: float | None = None,
        proveedor: str | None = None,
        operacion: str | None = None,
        modelo: str | None = None,
    ) -> None:
        """Acepta el `usage` de un chat (objeto OpenAI o dict; tolerante a
        campos faltantes). Acumula tokens (para mostrar) y el COSTO del
        request con el precio del MODELO usado. Si no se pasan precios, usa
        los de gpt-4o-mini (compat). `operacion` etiqueta la telemetría (si es
        None, se lee del ContextVar); `modelo` solo alimenta el log."""
        if usage is None:
            return
        prompt = int(_get(usage, "prompt_tokens", 0) or 0)
        completion = int(_get(usage, "completion_tokens", 0) or 0)
        # Detalle de cached tokens — soportado cuando el prompt caching aplica.
        cached = 0
        details = _get(usage, "prompt_tokens_details", None)
        if details is not None:
            cached = int(_get(details, "cached_tokens", 0) or 0)

        p_in = _PRECIO_INPUT_POR_M if precio_input_por_m is None else precio_input_por_m
        p_out = _PRECIO_OUTPUT_POR_M if precio_output_por_m is None else precio_output_por_m
        # El input cacheado suele costar la mitad; si no nos dan precio, lo
        # derivamos del de input.
        p_cached = (
            (p_in / 2.0) if precio_cached_por_m is None else precio_cached_por_m
        )
        no_cache = max(0, prompt - cached)
        inc = (
            no_cache * p_in + cached * p_cached + completion * p_out
        ) / 1_000_000

        op = operacion if operacion is not None else operacion_ctx.get()
        with self._lock:
            self._s.prompt_tokens += prompt
            self._s.completion_tokens += completion
            self._s.cached_prompt_tokens += cached
            self._s.costo_chat_usd += inc
            self._s.llamadas_chat += 1
            if proveedor == "anthropic":
                self._s.costo_chat_anthropic_usd += inc
                self._s.llamadas_chat_anthropic += 1
            elif proveedor == "openai":
                self._s.costo_chat_openai_usd += inc
                self._s.llamadas_chat_openai += 1
            self._acc_op(op, tokens_in=prompt, tokens_out=completion, cached=cached, costo=inc)
        logger.info(
            "llm_uso op=%s proveedor=%s modelo=%s in=%d out=%d cached=%d costo_usd=%.6f",
            op, proveedor or "?", modelo or "?", prompt, completion, cached, inc,
        )

    def _acc_op(
        self, op: str, *, tokens_in: int, tokens_out: int, cached: int, costo: float
    ) -> None:
        """Acumula el desglose por operación. Se llama con el lock TOMADO."""
        e = self._s.por_operacion.get(op)
        if e is None:
            e = {"llamadas": 0, "tokens_in": 0, "tokens_out": 0, "cached": 0, "costo_usd": 0.0}
            self._s.por_operacion[op] = e
        e["llamadas"] += 1
        e["tokens_in"] += tokens_in
        e["tokens_out"] += tokens_out
        e["cached"] += cached
        e["costo_usd"] += costo

    def registrar_whisper(self, segundos: float, *, operacion: str = "whisper") -> None:
        if segundos <= 0:
            return
        costo = (float(segundos) / 60.0) * _PRECIO_WHISPER_POR_MIN
        with self._lock:
            self._s.segundos_whisper += float(segundos)
            self._s.llamadas_whisper += 1
            self._acc_op(operacion, tokens_in=0, tokens_out=0, cached=0, costo=costo)
        logger.info("llm_uso op=%s segundos=%.1f costo_usd=%.6f", operacion, float(segundos), costo)

    def registrar_tts(self, caracteres: int, *, operacion: str = "tts") -> None:
        if caracteres <= 0:
            return
        costo = int(caracteres) * _PRECIO_TTS_POR_M_CHARS / 1_000_000
        with self._lock:
            self._s.caracteres_tts += int(caracteres)
            self._s.llamadas_tts += 1
            self._acc_op(operacion, tokens_in=0, tokens_out=0, cached=0, costo=costo)
        logger.info("llm_uso op=%s chars=%d costo_usd=%.6f", operacion, int(caracteres), costo)

    def registrar_embedding(self, tokens: int, *, operacion: str = "embedding") -> None:
        if tokens <= 0:
            return
        costo = int(tokens) * _PRECIO_EMBED_POR_M / 1_000_000
        with self._lock:
            self._s.tokens_embedding += int(tokens)
            self._s.llamadas_embedding += 1
            self._acc_op(operacion, tokens_in=int(tokens), tokens_out=0, cached=0, costo=costo)
        logger.info("llm_uso op=%s in=%d out=0 costo_usd=%.6f", operacion, int(tokens), costo)

    def registrar_busqueda_web(self, n: int = 1) -> None:
        if n <= 0:
            return
        with self._lock:
            self._s.llamadas_busqueda_web += int(n)

    def snapshot(self) -> dict[str, Any]:
        """Devuelve el estado actual + costo estimado en USD."""
        with self._lock:
            s = _Snapshot(**self._s.__dict__)
            por_op = {k: dict(v) for k, v in self._s.por_operacion.items()}
        # El costo del CHAT (incluye visión) ya viene acumulado por request con
        # el precio del modelo usado. Whisper/TTS/embeddings/Tavily a precio fijo.
        costo_whisper = (s.segundos_whisper / 60.0) * _PRECIO_WHISPER_POR_MIN
        costo_tts = s.caracteres_tts * _PRECIO_TTS_POR_M_CHARS / 1_000_000
        costo_embed = s.tokens_embedding * _PRECIO_EMBED_POR_M / 1_000_000
        costo_tavily = s.llamadas_busqueda_web * _PRECIO_TAVILY_POR_BUSQUEDA
        # Desglose por categoría (USD acumulado del proceso). Lo usa el
        # monitoreo de costo persistido (costos.py) para sumar por día/mes.
        costos = {
            "chat": round(s.costo_chat_usd, 6),
            "whisper": round(costo_whisper, 6),
            "tts": round(costo_tts, 6),
            "embedding": round(costo_embed, 6),
            "tavily": round(costo_tavily, 6),
        }
        costo = s.costo_chat_usd + costo_whisper + costo_tts + costo_embed + costo_tavily
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
            "tokens_embedding": s.tokens_embedding,
            "llamadas_embedding": s.llamadas_embedding,
            "llamadas_busqueda_web": s.llamadas_busqueda_web,
            "costo_usd": round(costo, 6),
            "costos": costos,
            # Desglose por OPERACIÓN (chat/vision:*/extraccion:*/repaso/embedding/
            # whisper/tts): tokens y costo acumulados por cada tipo de llamada.
            "por_operacion": {
                k: {**v, "costo_usd": round(v["costo_usd"], 6)} for k, v in por_op.items()
            },
            # Desglose del chat/visión por proveedor (observabilidad del failover).
            "por_proveedor": {
                "openai": {
                    "costo_usd": round(s.costo_chat_openai_usd, 6),
                    "llamadas": s.llamadas_chat_openai,
                },
                "anthropic": {
                    "costo_usd": round(s.costo_chat_anthropic_usd, 6),
                    "llamadas": s.llamadas_chat_anthropic,
                },
            },
            # Útil para la UI: precios usados para el cálculo.
            "precios": {
                "input_por_m_usd": _PRECIO_INPUT_POR_M,
                "input_cached_por_m_usd": _PRECIO_INPUT_CACHED_POR_M,
                "output_por_m_usd": _PRECIO_OUTPUT_POR_M,
                "whisper_por_min_usd": _PRECIO_WHISPER_POR_MIN,
                "tts_por_m_chars_usd": _PRECIO_TTS_POR_M_CHARS,
                "embedding_por_m_usd": _PRECIO_EMBED_POR_M,
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
