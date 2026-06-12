"""Secretos de runtime — env var PRIMERO, tabla `secretos_runtime` como fallback.

Caso de uso: integraciones (Spotify) cuyas credenciales no se pudieron poner
como variables de entorno en Railway. La tabla tiene RLS sin políticas: solo
el service role (el cerebro) puede leerla. Los VALORES jamás se loggean.
"""
from __future__ import annotations

import logging
import os
import time
from typing import Any

import httpx

log = logging.getLogger(__name__)

_TTL_S = 300.0
# Caché: clave -> (valor | None, expira_monotonic).
_cache: dict[str, tuple[str | None, float]] = {}


def _limpiar_cache() -> None:
    """Para los tests."""
    _cache.clear()


async def obtener(clave: str, cliente: httpx.AsyncClient | None = None) -> str | None:
    """Valor del secreto `clave`: env var del mismo nombre si existe; si no,
    la tabla `secretos_runtime` (cacheado 5 min). None si no está en ninguna."""
    en_env = os.getenv(clave)
    if en_env:
        return en_env
    hit = _cache.get(clave)
    if hit and hit[1] > time.monotonic():
        return hit[0]
    url = os.getenv("SUPABASE_URL")
    srk = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not srk:
        return None
    try:
        propio = cliente is None
        cli = cliente or httpx.AsyncClient(timeout=6.0)
        try:
            r = await cli.get(
                f"{url}/rest/v1/secretos_runtime",
                params={"clave": f"eq.{clave}", "select": "valor"},
                headers={"apikey": srk, "Authorization": f"Bearer {srk}"},
            )
        finally:
            if propio:
                await cli.aclose()
        valor: str | None = None
        if r.status_code == 200:
            filas = r.json() or []
            if filas:
                valor = filas[0].get("valor") or None
        else:
            log.warning("secretos_runtime devolvió %s para «%s»", r.status_code, clave)
        _cache[clave] = (valor, time.monotonic() + _TTL_S)
        return valor
    except httpx.HTTPError as e:
        log.warning("secretos_runtime inalcanzable (%s) para «%s»", type(e).__name__, clave)
        return None
