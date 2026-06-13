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
import os
import time
from typing import Any
from urllib.parse import urlencode

import httpx

from . import secretos

log = logging.getLogger(__name__)

_URL_TOKEN = "https://accounts.spotify.com/api/token"
_URL_AUTORIZA = "https://accounts.spotify.com/authorize"
_API = "https://api.spotify.com/v1"
_TIMEOUT = 10.0

# Redirect URI: endpoint PÚBLICO del cerebro (Spotify redirige acá tras el
# consentimiento). Configurable por env/secreto; por defecto, producción.
_REDIRECT_DEFECTO = "https://matix-production.up.railway.app/api/v1/spotify/callback"
# Scopes mínimos para reproducir: ordenar play + leer el estado del player.
_SCOPES = "user-modify-playback-state user-read-playback-state"


async def redirect_uri() -> str:
    return await secretos.obtener("SPOTIFY_REDIRECT_URI") or _REDIRECT_DEFECTO

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


async def conectado() -> bool:
    """True si ya hay refresh token (el usuario autorizó). Para el botón de la
    app: muestra «Conectado» vs «Conectar Spotify»."""
    return bool(await secretos.obtener("SPOTIFY_REFRESH_TOKEN"))


async def url_de_autorizacion(state: str) -> str:
    """URL de consentimiento de Spotify (authorization code) que la app abre en
    el navegador del teléfono. `state` es la defensa CSRF (lo verifica el
    callback). Lanza RuntimeError si faltan client id/secret."""
    c = await _credenciales()
    if not c["SPOTIFY_CLIENT_ID"] or not c["SPOTIFY_CLIENT_SECRET"]:
        raise RuntimeError("Faltan SPOTIFY_CLIENT_ID/SECRET en el cerebro.")
    params = {
        "client_id": c["SPOTIFY_CLIENT_ID"],
        "response_type": "code",
        "redirect_uri": await redirect_uri(),
        "scope": _SCOPES,
        "state": state,
    }
    return f"{_URL_AUTORIZA}?{urlencode(params)}"


async def intercambiar_code(code: str, cliente: httpx.AsyncClient | None = None) -> bool:
    """Cierra el OAuth: intercambia `code` por tokens y GUARDA el refresh token
    en secretos_runtime (nunca lo loggea). Devuelve True si quedó conectado.
    Tras esto, `playback_disponible()` pasa a True."""
    c = await _credenciales()
    cid, sec = c["SPOTIFY_CLIENT_ID"], c["SPOTIFY_CLIENT_SECRET"]
    if not cid or not sec:
        return False
    basic = base64.b64encode(f"{cid}:{sec}".encode()).decode()
    data = {
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": await redirect_uri(),
    }
    try:
        async with _cliente(cliente) as (cli, _propio):
            r = await cli.post(_URL_TOKEN, data=data, headers={"Authorization": f"Basic {basic}"})
        if r.status_code != 200:
            log.warning("spotify intercambiar_code devolvió %s", r.status_code)
            return False
        refresh = r.json().get("refresh_token")
        if not refresh:
            log.warning("spotify intercambiar_code: sin refresh_token en la respuesta")
            return False
    except (httpx.HTTPError, ValueError) as e:
        log.warning("spotify intercambiar_code falló: %s", type(e).__name__)
        return False
    # Guardado en secretos_runtime (y en el entorno del proceso para que la
    # caché de _credenciales lo vea ya). El VALOR nunca se loggea.
    ok = await secretos.guardar("SPOTIFY_REFRESH_TOKEN", refresh)
    if ok:
        os.environ["SPOTIFY_REFRESH_TOKEN"] = refresh
        _tokens.pop("user", None)  # invalida un token de usuario viejo
    return ok


async def olvidar_refresh() -> None:
    """Desconecta: borra el refresh token (deja id/secret → la búsqueda sigue).
    Vacía el valor en secretos_runtime y el entorno + caché del token de usuario."""
    await secretos.guardar("SPOTIFY_REFRESH_TOKEN", "")
    os.environ.pop("SPOTIFY_REFRESH_TOKEN", None)
    _tokens.pop("user", None)


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
    except (httpx.HTTPError, ValueError) as e:
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
    except (httpx.HTTPError, ValueError) as e:
        log.warning("spotify search falló: %s", type(e).__name__)
        return None


async def _mensaje_sin_oauth() -> str:
    """Distingue «faltan credenciales» de «el token está vencido/revocado»."""
    muro = await que_falta_para_playback()
    return muro or (
        "el refresh token de Spotify parece vencido o revocado; reautoriza "
        "una vez con tools/spotify_autorizar_auto.py"
    )


async def _elegir_dispositivo(dispositivos: list[dict]) -> dict | None:
    """LA PC correcta: si hay varios Computer (laptop + PC), gana el que
    coincide con SPOTIFY_DEVICE_NAME (hostname de la PC del agente)."""
    nombre_pref = (await secretos.obtener("SPOTIFY_DEVICE_NAME") or "").strip().lower()
    # Reemplazo LIMPIO al cambiar de canción: entre las entradas de ESTA PC,
    # gana la ACTIVA (la que ya está sonando) — así el play la reemplaza en la
    # misma sesión en vez de abrir una segunda (Spotify a veces registra una
    # entrada duplicada al reconectar → si apuntáramos a la otra, sonarían DOS
    # a la vez). Orden: nuestra-PC-activa → nuestra-PC → Computer-activo →
    # Computer → activo → lo que haya. NO secuestramos la laptop si estuviera
    # activa: nuestra PC (por nombre) gana sobre un activo ajeno.
    def _es_nuestra(d: dict) -> bool:
        return bool(nombre_pref) and (d.get("name") or "").strip().lower() == nombre_pref

    nuestras_activas = [d for d in dispositivos if _es_nuestra(d) and d.get("is_active")]
    nuestras = [d for d in dispositivos if _es_nuestra(d)]
    compus_activos = [d for d in dispositivos if d.get("type") == "Computer" and d.get("is_active")]
    compus = [d for d in dispositivos if d.get("type") == "Computer"]
    activos = [d for d in dispositivos if d.get("is_active")]
    return (nuestras_activas or nuestras or compus_activos or compus or activos or dispositivos or [None])[0]


async def dispositivo_objetivo(cliente: httpx.AsyncClient | None = None) -> dict[str, Any] | None:
    """El dispositivo de ESTA PC según /me/player/devices, o None si el
    cliente de escritorio no está abierto/registrado (o no hay OAuth)."""
    token = await _token("user", cliente)
    if not token:
        return None
    try:
        async with _cliente(cliente) as (cli, _propio):
            r = await cli.get(f"{_API}/me/player/devices",
                              headers={"Authorization": f"Bearer {token}"})
        if r.status_code != 200:
            return None
        return await _elegir_dispositivo(r.json().get("devices") or [])
    except (httpx.HTTPError, ValueError):
        return None


def _track_de_estado(payload: dict) -> dict[str, Any] | None:
    """Extrae {nombre, artista, uri} del item de un `GET /me/player`."""
    item = (payload or {}).get("item") or {}
    if not item.get("uri"):
        return None
    return {
        "uri": item.get("uri"),
        "nombre": item.get("name"),
        "artista": ", ".join(a.get("name", "") for a in item.get("artists") or []),
    }


async def estado_reproduccion(cliente: httpx.AsyncClient | None = None) -> dict[str, Any]:
    """Estado REAL del player (`GET /me/player`): qué track suena y si está
    reproduciendo. La fuente autoritativa (mejor que el título de ventana).
    Devuelve {ok, is_playing, track|None, device}. ok=False si no hay OAuth o
    no hay sesión activa."""
    token = await _token("user", cliente)
    if not token:
        return {"ok": False, "tipo": "sin_oauth"}
    try:
        async with _cliente(cliente) as (cli, _propio):
            r = await cli.get(f"{_API}/me/player",
                              headers={"Authorization": f"Bearer {token}"})
        if r.status_code == 204:
            return {"ok": True, "is_playing": False, "track": None, "device": None}
        if r.status_code != 200:
            return {"ok": False, "tipo": "error_api", "mensaje": f"player devolvió {r.status_code}"}
        cuerpo = r.json()
        return {
            "ok": True,
            "is_playing": bool(cuerpo.get("is_playing")),
            "track": _track_de_estado(cuerpo),
            "device": (cuerpo.get("device") or {}).get("name"),
        }
    except (httpx.HTTPError, ValueError) as e:
        return {"ok": False, "tipo": "error_red", "mensaje": type(e).__name__}


# Acciones de control del player (sin reproducir un track nuevo): método + ruta.
_CONTROL = {
    "pausa": ("PUT", "me/player/pause"),
    "reanuda": ("PUT", "me/player/play"),
    "siguiente": ("POST", "me/player/next"),
    "anterior": ("POST", "me/player/previous"),
}


async def control_player(accion: str, cliente: httpx.AsyncClient | None = None) -> dict[str, Any]:
    """Controla el player SIN cambiar de track: pausa/reanuda/siguiente/anterior.
    Apunta al device de ESTA PC. Devuelve {ok, ...} y, salvo pausa, el track que
    quedó sonando (leído del estado real)."""
    accion = (accion or "").strip().lower()
    if accion not in _CONTROL:
        return {"ok": False, "tipo": "validacion",
                "mensaje": f"acción no reconocida: {accion} (usa pausa/reanuda/siguiente/anterior)"}
    token = await _token("user", cliente)
    if not token:
        return {"ok": False, "tipo": "sin_oauth", "mensaje": await _mensaje_sin_oauth()}
    auth = {"Authorization": f"Bearer {token}"}
    metodo, ruta = _CONTROL[accion]
    try:
        device = await dispositivo_objetivo(cliente)
        params = {"device_id": device["id"]} if device and device.get("id") else None
        async with _cliente(cliente) as (cli, _propio):
            rp = await cli.request(metodo, f"{_API}/{ruta}", params=params, headers=auth)
        if rp.status_code not in (200, 202, 204):
            if rp.status_code == 403:
                return {"ok": False, "tipo": "sin_premium",
                        "mensaje": "Spotify rechazó el control (403): la cuenta no permite control remoto"}
            if rp.status_code == 404:
                return {"ok": False, "tipo": "sin_dispositivo",
                        "mensaje": "no hay nada reproduciéndose en la PC ahora mismo"}
            return {"ok": False, "tipo": "error_api", "mensaje": f"{accion} devolvió {rp.status_code}"}
    except (httpx.HTTPError, ValueError) as e:
        return {"ok": False, "tipo": "error_red", "mensaje": type(e).__name__}
    salida: dict[str, Any] = {"ok": True, "accion": accion}
    if accion != "pausa":
        est = await estado_reproduccion(cliente)
        salida["track"] = est.get("track")
        salida["is_playing"] = est.get("is_playing")
    return salida


async def reproducir_en_pc(
    uri: str, cliente: httpx.AsyncClient | None = None
) -> dict[str, Any]:
    """Ordena reproducir `uri` en la COMPUTADORA del usuario vía la Web API
    (requiere Premium + SPOTIFY_REFRESH_TOKEN). Elige el dispositivo tipo
    Computer (el cliente de escritorio debe estar abierto)."""
    token = await _token("user", cliente)
    if not token:
        return {"ok": False, "tipo": "sin_oauth", "mensaje": await _mensaje_sin_oauth()}
    auth = {"Authorization": f"Bearer {token}"}
    try:
        async with _cliente(cliente) as (cli, _propio):
            r = await cli.get(f"{_API}/me/player/devices", headers=auth)
            if r.status_code != 200:
                return {"ok": False, "tipo": "error_api", "mensaje": f"devices devolvió {r.status_code}"}
            dispositivos = r.json().get("devices") or []
            elegido = await _elegir_dispositivo(dispositivos)
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
    except (httpx.HTTPError, ValueError) as e:
        log.warning("spotify play falló: %s", type(e).__name__)
        return {"ok": False, "tipo": "error_red", "mensaje": f"no pude hablar con Spotify ({type(e).__name__})"}
