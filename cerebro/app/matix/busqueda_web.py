"""Búsqueda web para Matix vía Tavily (Capa 2 · info ACTUAL / EXTERNA).

Provider-agnóstica: es una tool más del set; el modelo (OpenAI o Anthropic) la
llama igual y sintetiza la respuesta con SU voz — por eso pedimos a Tavily las
fuentes crudas (título, url, extracto) y NO su `answer` pre-generada.

Seguridad: la API key se lee SOLO de la variable de entorno `TAVILY_API_KEY`.
Nunca va en el código, el repo ni los logs (no logueamos la key ni el objeto
cliente; solo el TIPO de error si algo falla).
"""
from __future__ import annotations

import logging
import os
from typing import Any

import anyio

logger = logging.getLogger("matix.busqueda_web")

# search_depth básico = rápido y barato (suficiente para sintetizar). 5 fuentes.
MAX_RESULTADOS = 5
# Tope de chars por extracto: que el modelo tenga contexto sin inflar tokens.
MAX_EXTRACTO = 500


class BusquedaWebError(RuntimeError):
    """Falla recuperable de la búsqueda (sin key, red, rate limit, SDK ausente).

    El handler la traduce a un error amable para que el modelo lo diga sin
    crashear ("no pude buscar ahora mismo").
    """


def _tavily_search(api_key: str, consulta: str, max_resultados: int) -> dict[str, Any]:
    """Llamada CRUDA y SÍNCRONA a Tavily. Aislada en su propia función para
    poder mockearla en los tests sin tocar la red ni necesitar el SDK."""
    from tavily import TavilyClient  # import perezoso: el módulo carga sin el SDK

    cliente = TavilyClient(api_key=api_key)
    return cliente.search(
        query=consulta,
        search_depth="basic",
        max_results=max_resultados,
        include_answer=False,  # que sintetice el modelo de Matix, no Tavily
    )


def _limpiar(resp: dict[str, Any]) -> list[dict[str, str]]:
    """Convierte la respuesta de Tavily en fuentes limpias para el modelo."""
    fuentes: list[dict[str, str]] = []
    for r in (resp or {}).get("results") or []:
        url = (r.get("url") or "").strip()
        if not url:
            continue
        extracto = (r.get("content") or "").strip()
        if len(extracto) > MAX_EXTRACTO:
            extracto = extracto[:MAX_EXTRACTO].rstrip() + "…"
        fuentes.append(
            {
                "titulo": (r.get("title") or "").strip() or url,
                "url": url,
                "extracto": extracto,
            }
        )
    return fuentes


async def buscar(
    consulta: str, *, max_resultados: int = MAX_RESULTADOS
) -> list[dict[str, str]]:
    """Busca en la web y devuelve fuentes limpias `[{titulo, url, extracto}]`.

    Lanza [BusquedaWebError] si la consulta está vacía, falta la key, no está el
    SDK, o Tavily falla (red / rate limit). El SDK es síncrono: lo corremos en un
    hilo para no bloquear el event loop.
    """
    consulta = (consulta or "").strip()
    if not consulta:
        raise BusquedaWebError("La consulta está vacía.")

    api_key = os.environ.get("TAVILY_API_KEY", "").strip()
    if not api_key:
        raise BusquedaWebError("No hay TAVILY_API_KEY configurada en el cerebro.")

    n = max(1, min(int(max_resultados or MAX_RESULTADOS), 10))
    try:
        resp = await anyio.to_thread.run_sync(
            _tavily_search, api_key, consulta, n
        )
    except ImportError as e:  # falta tavily-python en el server
        logger.warning("Tavily no disponible: %s", type(e).__name__)
        raise BusquedaWebError("Falta el SDK de búsqueda en el cerebro.") from e
    except Exception as e:  # noqa: BLE001 — red, rate limit, key inválida…
        # No logueamos el objeto/key, solo el tipo de error.
        logger.warning("Tavily falló: %s", type(e).__name__)
        raise BusquedaWebError("La búsqueda web no respondió.") from e

    # Monitoreo de costo: una búsqueda exitosa cuenta para el gasto del día.
    from .uso import medidor
    medidor.registrar_busqueda_web(1)

    return _limpiar(resp)
