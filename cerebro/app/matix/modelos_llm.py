"""Catálogo curado de modelos del LLM de chat + selección.

Una lista FIJA de los modelos principales de cada proveedor, con su id real
de API, un nombre amigable y el precio por token (para el medidor). La app la
consume vía `GET /modelos` y guarda la selección en `config_matix.modelo_chat`.

El proveedor NO se guarda aparte: se INFIERE del id (`claude-*` → anthropic;
`gpt-*` / `o1`/`o3`/`o4` → openai). El usuario elige el modelo; el cerebro
rutea al proveedor correcto.

IDs:
- OpenAI: verificados contra `/v1/models` (2026-05).
- Anthropic: convención `claude-<tier>-4-<minor>` (el `claude-opus-4-8` es el
  modelo de referencia). Si alguno cambia, se edita ACÁ — un solo lugar.

Precios (USD por 1M tokens, input/output): ESTIMADOS para los modelos nuevos
(el endpoint de modelos no trae precios). El medidor ya marca el costo como
"estimado". Editar acá si cambian.
"""
from __future__ import annotations

from dataclasses import dataclass

from ..db import Postgrest
from ..config import settings


@dataclass(frozen=True)
class ModeloLLM:
    id: str            # id real de la API del proveedor
    etiqueta: str      # nombre amigable para la app
    proveedor: str     # "openai" | "anthropic"
    precio_input_por_m: float   # USD / 1M tokens de input
    precio_output_por_m: float  # USD / 1M tokens de output


# Lista curada. El orden define el orden en la app (dentro de cada proveedor).
MODELOS: list[ModeloLLM] = [
    # ── OpenAI (ids verificados vía /v1/models) ──
    ModeloLLM("gpt-5.5", "GPT-5.5", "openai", 1.25, 10.0),
    ModeloLLM("gpt-5.4-mini", "GPT-5.4 mini", "openai", 0.25, 2.0),
    ModeloLLM("gpt-5.4-nano", "GPT-5.4 nano", "openai", 0.05, 0.40),
    ModeloLLM("gpt-4o-mini", "GPT-4o mini", "openai", 0.15, 0.60),
    # ── Anthropic (convención claude-<tier>-4-<minor>) ──
    ModeloLLM("claude-opus-4-8", "Claude Opus 4.8", "anthropic", 15.0, 75.0),
    ModeloLLM("claude-opus-4-7", "Claude Opus 4.7", "anthropic", 15.0, 75.0),
    ModeloLLM("claude-sonnet-4-6", "Claude Sonnet 4.6", "anthropic", 3.0, 15.0),
    ModeloLLM("claude-haiku-4-5", "Claude Haiku 4.5", "anthropic", 1.0, 5.0),
]

_POR_ID = {m.id: m for m in MODELOS}


def proveedor_de_id(modelo_id: str | None) -> str:
    """Infiere el proveedor del id del modelo. Si no se reconoce, cae al
    proveedor del env (`MATIX_LLM_PROVIDER`) y, si tampoco, a openai."""
    m = (modelo_id or "").strip().lower()
    if m.startswith("claude"):
        return "anthropic"
    if m.startswith(("gpt", "o1", "o3", "o4", "chatgpt")):
        return "openai"
    # Si el id está en el catálogo, manda su proveedor explícito.
    cat = _POR_ID.get(modelo_id or "")
    if cat:
        return cat.proveedor
    return (settings.matix_llm_provider or "openai").strip().lower() or "openai"


def modelo_por_id(modelo_id: str | None) -> ModeloLLM | None:
    return _POR_ID.get(modelo_id or "")


def precios_de(modelo_id: str | None) -> tuple[float, float] | None:
    """(input, output) por 1M tokens del modelo, o None si no está en el
    catálogo (el medidor usa entonces su default)."""
    m = _POR_ID.get(modelo_id or "")
    return (m.precio_input_por_m, m.precio_output_por_m) if m else None


def listar() -> list[dict]:
    """El catálogo para la app: id + etiqueta + proveedor."""
    return [
        {"id": m.id, "etiqueta": m.etiqueta, "proveedor": m.proveedor}
        for m in MODELOS
    ]


# ── Selección (persistida en config_matix.modelo_chat) ──────────────


async def _fila(db: Postgrest) -> dict | None:
    filas = await db.list("config_matix", limit=1)
    return filas[0] if filas else None


async def modelo_seleccionado(db: Postgrest) -> str:
    """El modelo de chat ACTIVO: lo que eligió la app (config_matix), o el
    del env (`MATIX_LLM_MODEL`) como fallback, o gpt-4o-mini en último caso.
    Si el guardado ya no está en el catálogo (se quitó), cae al fallback."""
    fila = await _fila(db)
    guardado = (fila or {}).get("modelo_chat")
    if guardado and guardado in _POR_ID:
        return guardado
    return settings.matix_llm_model or "gpt-4o-mini"


async def set_modelo(db: Postgrest, modelo_id: str) -> None:
    """Fija el modelo de chat en config_matix. Valida contra el catálogo."""
    if modelo_id not in _POR_ID:
        raise ValueError(f"Modelo desconocido: {modelo_id}")
    fila = await _fila(db)
    if fila is None:
        await db.insert("config_matix", {"modelo_chat": modelo_id})
    else:
        await db.update("config_matix", fila["id"], {"modelo_chat": modelo_id})
