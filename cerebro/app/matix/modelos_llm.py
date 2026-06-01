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

# Selección especial "Automático": el cerebro elige el modelo por mensaje
# (ver `enrutador.py`). Se guarda LITERAL en config_matix.modelo_chat.
AUTO = "auto"

# Defaults del par barato/fuerte que usa el modo Automático. Editables desde
# la app (config_matix.modelo_barato/modelo_fuerte); estos son el fallback.
#   barato = comandos/CRUD/preguntas rápidas y todo el texto de fondo.
#   fuerte = escritura/razonamiento/análisis y los modos pesados.
DEFAULT_BARATO = "gpt-4o-mini"
DEFAULT_FUERTE = "claude-sonnet-4-6"


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


def etiqueta_de(modelo_id: str | None) -> str:
    """Nombre amigable del modelo (ej. «Claude Sonnet 4.6»). Si el id no está
    en el catálogo, devuelve el id tal cual — nunca vacío."""
    m = _POR_ID.get(modelo_id or "")
    return m.etiqueta if m else (modelo_id or "desconocido")


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


def _fallback_concreto() -> str:
    """El modelo concreto por defecto (nunca 'auto'): el del env o gpt-4o-mini."""
    env = settings.matix_llm_model
    return env if env and env in _POR_ID else DEFAULT_BARATO


async def seleccion_guardada(db: Postgrest) -> str:
    """Lo que el usuario tiene seleccionado: un id del catálogo o el literal
    `"auto"` (modo Automático). Si el guardado ya no es válido, cae a un
    modelo concreto de fallback. Esto es lo que la app muestra como
    "seleccionado" y lo que `chat.py` consulta para saber si rutear."""
    guardado = ((await _fila(db)) or {}).get("modelo_chat")
    if guardado == AUTO or (guardado and guardado in _POR_ID):
        return guardado
    return _fallback_concreto()


async def modelo_seleccionado(db: Postgrest) -> str:
    """Un modelo CONCRETO (nunca 'auto') para tareas que no son la
    conversación con ruteo — captura rápida, etc. Si la selección es
    Automático, devuelve el modelo barato del par (clasificar/CRUD no
    necesita el fuerte y así no disparamos el costo)."""
    sel = await seleccion_guardada(db)
    if sel == AUTO:
        barato, _ = await par_barato_fuerte(db)
        return barato
    return sel


async def par_barato_fuerte(db: Postgrest) -> tuple[str, str]:
    """El par (barato, fuerte) que usa el modo Automático. Se lee de
    config_matix; cada lado cae a su default si está vacío o ya no existe."""
    fila = await _fila(db) or {}
    barato = fila.get("modelo_barato")
    fuerte = fila.get("modelo_fuerte")
    return (
        barato if barato in _POR_ID else DEFAULT_BARATO,
        fuerte if fuerte in _POR_ID else DEFAULT_FUERTE,
    )


async def modelo_fondo(db: Postgrest) -> str:
    """El modelo para TODO el texto de fondo (briefing, repaso, nudges…):
    SIEMPRE el barato, nunca el auto ni el fuerte, para no disparar el
    costo en lo que se genera sin que el usuario esté mirando."""
    barato, _ = await par_barato_fuerte(db)
    return barato


def es_seleccion_valida(valor: str) -> bool:
    return valor == AUTO or valor in _POR_ID


async def set_seleccion(db: Postgrest, valor: str) -> None:
    """Fija la selección en config_matix: un id del catálogo o `"auto"`."""
    if not es_seleccion_valida(valor):
        raise ValueError(f"Selección desconocida: {valor}")
    fila = await _fila(db)
    if fila is None:
        await db.insert("config_matix", {"modelo_chat": valor})
    else:
        await db.update("config_matix", fila["id"], {"modelo_chat": valor})


# Alias retro-compat (el router viejo llamaba `set_modelo`).
set_modelo = set_seleccion


async def set_par(
    db: Postgrest, *, barato: str | None = None, fuerte: str | None = None
) -> None:
    """Cambia el par barato/fuerte del modo Automático. Valida cada id
    contra el catálogo; ignora los `None` (cambio parcial)."""
    payload: dict[str, str] = {}
    if barato is not None:
        if barato not in _POR_ID:
            raise ValueError(f"Modelo barato desconocido: {barato}")
        payload["modelo_barato"] = barato
    if fuerte is not None:
        if fuerte not in _POR_ID:
            raise ValueError(f"Modelo fuerte desconocido: {fuerte}")
        payload["modelo_fuerte"] = fuerte
    if not payload:
        return
    fila = await _fila(db)
    if fila is None:
        await db.insert("config_matix", payload)
    else:
        await db.update("config_matix", fila["id"], payload)
