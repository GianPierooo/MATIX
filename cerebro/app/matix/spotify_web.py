"""Spotify Web API — búsqueda de tracks y orden de reproducción REAL.

Dos niveles de credenciales (variables de entorno, nunca en código):
  - SPOTIFY_CLIENT_ID + SPOTIFY_CLIENT_SECRET → token client-credentials:
    alcanza para BUSCAR («cualquier canción de X» → el track más popular).
  - + SPOTIFY_REFRESH_TOKEN (OAuth del usuario, cuenta Premium) → token de
    usuario: alcanza para ORDENAR reproducir en un dispositivo
    (PUT /v1/me/player/play). Es la ÚNICA vía garantizada de que SUENE:
    abrir spotify:track:… en el cliente solo navega, no auto-reproduce
    (verificado empíricamente en la PC del usuario).

El refresh token se obtiene UNA vez con `tools/spotify_autorizar.py` (consent
del usuario en su navegador) y va a Railway + cerebro/.env. Nunca se loggea.
"""
from __future__ import annotations

import base64
import logging
import time
from typing import Any

import httpx

from . import secretos

log = logging.getLogger(__name__)

_URL_TOKEN = "https://accounts.spotify.com/api/token"
_API = "https://api.spotify.com/v1"
_TIMEOUT = 10.0

# Caché de tokens por modo ("cc" | "user"): (token, expira_monotonic).
_tokens: dict[str, tuple[str, float]] = {}

_CLAVES = ("SPOTIFY_CLIENT_ID", "SPOTIFY_CLIENT_SECRET", "SPOTIFY_REFRESH_TOKEN")


async def _credenciales() -> dict[str, str | None]:
    """Las tres credenciales, cada una de env var o de `secretos_runtime`
    (fallback en Supabase, solo service role). Los valores NUNCA se loggean."""
    return {clave: await secretos.obtener(clave) for clave in _CLAVES}


async def busqueda_disponible() -> bool:
    c = await _credenciales()
    return bool(c["SPOTIFY_CLIENT_ID"] and c["SPOTIFY_CLIENT_SECRET"])


async def playback_disponible() -> bool:
    c = await _credenciales()
    return all(c.values())


async def que_falta_para_playback() -> str:
    """Nombres (solo NOMBRES) de las credenciales que faltan para poder ordenar
    reproducción real. Texto listo para narrar al usuario."""
    c = await _credenciales()
    faltan = [clave for clave in _CLAVES if not c[clave]]
    if not faltan:
        return ""
    return (
        "falta configurar la Web API de Spotify en el cerebro ("
        + ", ".join(faltan)
        + "; se obtienen creando una app en developer.spotify.com y corriendo "
        "tools/spotify_autorizar.py una sola vez)"
    )


def _limpiar_cache() -> None:
    """Para los tests."""
    _tokens.clear()


async def _token(modo: str, cliente: httpx.AsyncClient | None = None) -> str | None:
    """Token de acceso ("cc" = client credentials para buscar; "user" = refresh
    token del usuario para playback). Cacheado hasta su expiración."""
    en_cache = _tokens.get(modo)
    if en_cache and en_cache[1] > time.monotonic():
        return en_cache[0]
    c = await _credenciales()
    cid, sec = c["SPOTIFY_CLIENT_ID"], c["SPOTIFY_CLIENT_SECRET"]
    if not cid or not sec:
        return None
    if modo == "user":
        refresh = c["SPOTIFY_REFRESH_TOKEN"]
        if not refresh:
            return None
        data = {"grant_type": "refresh_token", "refresh_token": refresh}
    else:
        data = {"grant_type": "client_credentials"}
    basic = base64.b64encode(f"{cid}:{sec}".encode()).decode()
    try:
        async with _cliente(cliente) as (cli, _propio):
            r = await cli.post(_URL_TOKEN, data=data, headers={"Authorization": f"Basic {basic}"})
        if r.status_code != 200:
            log.warning("spotify token (%s) devolvió %s", modo, r.status_code)
            return None
        cuerpo = r.json()
        token = cuerpo.get("access_token")
        if not token:
            return None
        vida = float(cuerpo.get("expires_in") or 3600)
        _tokens[modo] = (token, time.monotonic() + vida - 60)
        return token
    except httpx.HTTPError as e:
        log.warning("spotify token (%s) falló: %s", modo, type(e).__name__)
        return None


class _cliente:
    """Context manager: usa el cliente inyectado (tests) o crea uno propio."""

    def __init__(self, cliente: httpx.AsyncClient | None) -> None:
        self._inyectado = cliente
        self._propio: httpx.AsyncClient | None = None

    async def __aenter__(self) -> tuple[httpx.AsyncClient, bool]:
        if self._inyectado is not None:
            return self._inyectado, False
        self._propio = httpx.AsyncClient(timeout=_TIMEOUT)
        return self._propio, True

    async def __aexit__(self, *exc: object) -> None:
        if self._propio is not None:
            await self._propio.aclose()


async def buscar_mejor_track(
    consulta: str, cliente: httpx.AsyncClient | None = None
) -> dict[str, Any] | None:
    """El track MÁS POPULAR que matchea la consulta (artista o canción).
    «cualquier canción de Michael Jackson» → su track top. None si no hay
    credenciales, no hay resultados o la API falla (el caller degrada)."""
    token = await _token("cc", cliente)
    if not token:
        return None
    try:
        async with _cliente(cliente) as (cli, _propio):
            r = await cli.get(
                f"{_API}/search",
                params={"q": consulta, "type": "track", "limit": 10, "market": "PE"},
                headers={"Authorization": f"Bearer {token}"},
            )
        if r.status_code != 200:
            log.warning("spotify search devolvió %s", r.status_code)
            return None
        items = (r.json().get("tracks") or {}).get("items") or []
        if not items:
            return None
        mejor = max(items, key=lambda t: t.get("popularity") or 0)
        return {
            "id": mejor.get("id"),
            "uri": mejor.get("uri"),
            "nombre": mejor.get("name"),
            "artista": ", ".join(a.get("name", "") for a in mejor.get("artists") or []),
        }
    except httpx.HTTPError as e:
        log.warning("spotify search falló: %s", type(e).__name__)
        return None


async def reproducir_en_pc(
    uri: str, cliente: httpx.AsyncClient | None = None
) -> dict[str, Any]:
    """Ordena reproducir `uri` en la COMPUTADORA del usuario vía la Web API
    (requiere Premium + SPOTIFY_REFRESH_TOKEN). Elige el dispositivo tipo
    Computer (el cliente de escritorio debe estar abierto)."""
    token = await _token("user", cliente)
    if not token:
        return {"ok": False, "tipo": "sin_oauth", "mensaje": que_falta_para_playback()}
    auth = {"Authorization": f"Bearer {token}"}
    try:
        async with _cliente(cliente) as (cli, _propio):
            r = await cli.get(f"{_API}/me/player/devices", headers=auth)
            if r.status_code != 200:
                return {"ok": False, "tipo": "error_api", "mensaje": f"devices devolvió {r.status_code}"}
            dispositivos = r.json().get("devices") or []
            # LA PC correcta: si hay varios Computer (laptop + PC), gana el que
            # coincide con SPOTIFY_DEVICE_NAME (el hostname de la PC del agente).
            nombre_pref = (await secretos.obtener("SPOTIFY_DEVICE_NAME") or "").strip().lower()
            preferidos = [
                d for d in dispositivos
                if nombre_pref and (d.get("name") or "").strip().lower() == nombre_pref
            ]
            compus = [d for d in dispositivos if d.get("type") == "Computer"]
            elegido = (preferidos or compus or dispositivos or [None])[0]
            if not elegido:
                return {
                    "ok": False, "tipo": "sin_dispositivo",
                    "mensaje": "Spotify no reporta ningún dispositivo (¿el cliente está abierto?)",
                }
            # track/episode van como `uris`; album/playlist/show como `context_uri`.
            cuerpo: dict[str, Any] = (
                {"uris": [uri]} if uri.startswith(("spotify:track:", "spotify:episode:"))
                else {"context_uri": uri}
            )
            rp = await cli.put(
                f"{_API}/me/player/play",
                params={"device_id": elegido.get("id")},
                json=cuerpo,
                headers=auth,
            )
        if rp.status_code in (200, 202, 204):
            return {"ok": True, "dispositivo": elegido.get("name")}
        if rp.status_code == 403:
            return {"ok": False, "tipo": "sin_premium", "mensaje": "Spotify rechazó la orden (403): la cuenta no permite control remoto"}
        return {"ok": False, "tipo": "error_api", "mensaje": f"play devolvió {rp.status_code}"}
    except httpx.HTTPError as e:
        log.warning("spotify play falló: %s", type(e).__name__)
        return {"ok": False, "tipo": "error_red", "mensaje": f"no pude hablar con Spotify ({type(e).__name__})"}
