"""Router de integración Spotify (Capa 6 · reproducir en la PC).

OAuth authorization-code DESDE LA APP: el usuario toca «Conectar Spotify» en
Ajustes, la app abre la URL de consentimiento en el navegador del teléfono, y
Spotify redirige al `/callback` PÚBLICO del cerebro, que intercambia el code por
el refresh token y lo guarda en `secretos_runtime` (nunca lo imprime).

Endpoints:
- `GET /api/v1/spotify/status` — ¿ya conectado? (refresh token presente).
- `GET /api/v1/spotify/oauth/url` — URL de consentimiento para abrir.
- `GET /api/v1/spotify/callback` — Spotify redirige acá (PÚBLICO; el `state`
  es la defensa CSRF).
- `DELETE /api/v1/spotify/disconnect` — borra el refresh token.

Todos requieren `X-Matix-Key` EXCEPTO `/callback` (Spotify no manda la header).
"""
from __future__ import annotations

import secrets
import time

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import HTMLResponse

from ..matix import spotify_web
from ..security import require_api_key

router = APIRouter(
    prefix="/spotify",
    tags=["spotify"],
    dependencies=[Depends(require_api_key)],
)

# Router separado para el callback, SIN auth (Spotify no manda X-Matix-Key).
router_callback = APIRouter(prefix="/spotify", tags=["spotify"])

# states pendientes del round-trip (defensa CSRF), con TTL. Single-user +
# 1 réplica → dict en memoria alcanza (mismo criterio que Google).
_PENDING_STATES: dict[str, float] = {}
_STATE_TTL_SEG = 600


def _prune() -> None:
    ahora = time.monotonic()
    for s in [s for s, t in _PENDING_STATES.items() if ahora - t > _STATE_TTL_SEG]:
        _PENDING_STATES.pop(s, None)


@router.get("/status")
async def estado() -> dict[str, bool]:
    return {
        "conectado": await spotify_web.conectado(),
        "busqueda_disponible": await spotify_web.busqueda_disponible(),
    }


@router.get("/oauth/url")
async def construir_url() -> dict[str, str]:
    """URL de consentimiento que la app abre en el navegador del teléfono."""
    _prune()
    state = secrets.token_urlsafe(24)
    try:
        url = await spotify_web.url_de_autorizacion(state)
    except RuntimeError as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(e)
        ) from e
    _PENDING_STATES[state] = time.monotonic()
    return {"url": url, "state": state}


@router_callback.get("/callback", response_class=HTMLResponse)
async def callback(
    code: str | None = Query(default=None),
    state: str = Query(...),
    error: str | None = Query(default=None),
) -> HTMLResponse:
    """Spotify redirige acá tras el consentimiento. Intercambia el code por el
    refresh token y muestra una página de resultado."""
    if error:
        return HTMLResponse(_pagina(ok=False, mensaje=f"Spotify reportó: {error}"), status_code=400)
    _prune()
    if _PENDING_STATES.pop(state, None) is None:
        return HTMLResponse(_pagina(
            ok=False,
            mensaje=("El enlace expiró o no coincide (más de 10 min, otro "
                     "dispositivo, o el cerebro se reinició). Vuelve a tocar "
                     "«Conectar Spotify» en Matix."),
        ), status_code=400)
    if not code:
        return HTMLResponse(_pagina(ok=False, mensaje="Spotify no devolvió el código."), status_code=400)
    try:
        ok = await spotify_web.intercambiar_code(code)
    except Exception as e:  # noqa: BLE001
        return HTMLResponse(_pagina(ok=False, mensaje=f"No se pudo completar: {e}"), status_code=500)
    if not ok:
        return HTMLResponse(_pagina(
            ok=False,
            mensaje="No pude guardar la conexión. Reintenta desde Matix.",
        ), status_code=500)
    return HTMLResponse(_pagina(
        ok=True,
        mensaje=("Spotify quedó conectado. Vuelve a Matix y pídeme que ponga "
                 "una canción en tu compu."),
    ))


@router.delete("/disconnect", status_code=status.HTTP_204_NO_CONTENT)
async def desconectar() -> None:
    """Borra el refresh token (deja la búsqueda; quita el playback). El grant en
    Spotify se revoca desde la cuenta del usuario."""
    await spotify_web.olvidar_refresh()


def _pagina(*, ok: bool, mensaje: str) -> str:
    color = "#1DB954" if ok else "#FF4D5E"  # verde Spotify / rojo
    titulo = "✓ Conectado" if ok else "✗ Algo falló"
    return f"""<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Matix · Spotify</title>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #0B0F1A; color: #E8ECF4; margin: 0; padding: 32px 20px;
      display: flex; flex-direction: column; align-items: center; min-height: 100vh;
      box-sizing: border-box; }}
    .card {{ background: #161B2E; border: 1px solid rgba(255,255,255,0.06);
      border-radius: 16px; padding: 28px 24px; max-width: 420px; width: 100%; margin-top: 60px; }}
    .titulo {{ font-size: 22px; font-weight: 700; color: {color}; margin: 0 0 12px; }}
    .mensaje {{ font-size: 15px; line-height: 1.5; margin: 0 0 20px; }}
    .cta {{ font-size: 13px; color: #8A93A8; margin: 0; }}
  </style>
</head>
<body>
  <div class="card">
    <h1 class="titulo">{titulo}</h1>
    <p class="mensaje">{mensaje}</p>
    <p class="cta">Puedes cerrar esta pestaña.</p>
  </div>
</body>
</html>
"""
