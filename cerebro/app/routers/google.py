"""Router de integración Google (Capa 4 Paso 1).

Endpoints:

- `GET /api/v1/google/status` — estado de la conexión.
- `GET /api/v1/google/oauth/url` — devuelve la URL de consentimiento
  para que la app la abra en el navegador.
- `GET /api/v1/google/oauth/callback` — Google redirige acá tras la
  autorización. Intercambia el `code`, guarda tokens, muestra una
  página de éxito y el usuario vuelve manual a la app.
- `POST /api/v1/google/sync` — fuerza un sync ahora.
- `DELETE /api/v1/google/disconnect` — borra los tokens.

Todos requieren `X-Matix-Key` EXCEPTO `/oauth/callback`, que es
público porque Google lo invoca directamente desde el navegador
del usuario y no puede mandar la auth header. Como el callback
verifica el `state` que generamos al armar la URL, esa es la
defensa contra ataques CSRF.
"""
from __future__ import annotations

import secrets
import time
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import HTMLResponse

from ..config import settings
from ..db import Postgrest, get_db
from ..google import calendar as gcal
from ..google import oauth as goauth
from ..schemas.google import GoogleStatusRead, GoogleSyncRead
from ..security import require_api_key

# Endpoints con auth — todos menos el callback.
router = APIRouter(
    prefix="/google",
    tags=["google"],
    dependencies=[Depends(require_api_key)],
)

# Router separado para el callback, sin la dependencia de auth
# (Google no manda nuestra API key). El `state` es la defensa.
router_callback = APIRouter(prefix="/google", tags=["google"])

# Estados pendientes del round-trip de OAuth, indexados por el `state`
# que generamos. Cada entrada guarda el `code_verifier` de PKCE — sin
# esto, el callback no puede cerrar el intercambio code→tokens y
# Google rechaza con `invalid_grant: Missing code verifier`.
#
# Single-user app + Railway con 1 replica = dict en memoria alcanza.
# Si en el futuro hay escalado horizontal, esto va a Supabase con TTL.
_PENDING_STATES: dict[str, dict[str, Any]] = {}

# TTL del state pendiente: 10 minutos. El usuario tiene que aprobar
# el consentimiento en ese plazo; pasado eso, la entrada se cae para
# no acumular basura en memoria.
_STATE_TTL_SEG = 600


def _prune_estados_viejos() -> None:
    """Elimina states con más de `_STATE_TTL_SEG` de antigüedad.
    Lo invocamos en cada generación/lookup para mantener el dict
    chico sin necesidad de un task de background."""
    ahora = time.monotonic()
    expirados = [
        s
        for s, info in _PENDING_STATES.items()
        if ahora - info["creado_en"] > _STATE_TTL_SEG
    ]
    for s in expirados:
        _PENDING_STATES.pop(s, None)


def _no_configurado() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail=(
            "OAuth Google no está habilitado en el cerebro. "
            "Configurá GOOGLE_CLIENT_ID/SECRET/REDIRECT_URI."
        ),
    )


@router.get("/status", response_model=GoogleStatusRead)
async def estado(db: Postgrest = Depends(get_db)) -> dict[str, Any]:
    cuenta = await goauth.cuenta_conectada(db)
    if cuenta is None:
        return {"conectado": False}
    return {"conectado": True, **cuenta}


@router.get("/oauth/url")
async def construir_url_autorizacion() -> dict[str, str]:
    """Genera y devuelve la URL que la app le pasa al navegador.

    Guardamos en memoria el `state` (defensa CSRF) y el `code_verifier`
    de PKCE — el callback los necesita para cerrar el intercambio
    code→tokens con Google.
    """
    if not (
        settings.google_client_id
        and settings.google_client_secret
        and settings.google_redirect_uri
    ):
        raise _no_configurado()
    _prune_estados_viejos()
    state = secrets.token_urlsafe(24)
    try:
        url, code_verifier = goauth.url_de_autorizacion(state)
    except RuntimeError as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(e),
        ) from e
    _PENDING_STATES[state] = {
        "code_verifier": code_verifier,
        "creado_en": time.monotonic(),
    }
    return {"url": url, "state": state}


@router_callback.get("/oauth/callback", response_class=HTMLResponse)
async def callback(
    code: str = Query(...),
    state: str = Query(...),
    error: str | None = Query(default=None),
    db: Postgrest = Depends(get_db),
) -> HTMLResponse:
    """Google llama acá tras la autorización. Devolvemos HTML con
    instrucciones para que el usuario vuelva a la app."""
    if error:
        return HTMLResponse(_pagina_resultado(
            ok=False,
            mensaje=f"Google reportó error: {error}",
        ), status_code=400)

    _prune_estados_viejos()
    info = _PENDING_STATES.pop(state, None)
    if info is None:
        return HTMLResponse(_pagina_resultado(
            ok=False,
            mensaje=(
                "El state no coincide o expiró. Esto puede pasar si "
                "abriste el link de autorización en otro dispositivo, "
                "si tardaste más de 10 minutos en autorizar o si el "
                "cerebro se reinició mientras tanto. Volvé a tocar "
                "'Conectar Google' en la app."
            ),
        ), status_code=400)

    try:
        email = await goauth.completar_autorizacion(
            db,
            code=code,
            state=state,
            code_verifier=info["code_verifier"],
        )
    except Exception as e:  # noqa: BLE001
        return HTMLResponse(_pagina_resultado(
            ok=False,
            mensaje=f"No se pudo completar la autorización: {e}",
        ), status_code=500)

    # Sync inicial en mismo request para que cuando el usuario
    # vuelva a la app, los eventos ya estén ahí.
    try:
        resumen = await gcal.sincronizar(db, email)
        nota = (
            f"{resumen['creados']} eventos sincronizados, "
            f"{resumen['actualizados']} actualizados."
        )
    except Exception:  # noqa: BLE001
        nota = "Vas a poder forzar un sync desde Ajustes."

    return HTMLResponse(_pagina_resultado(
        ok=True,
        mensaje=(
            f"Cuenta conectada: <strong>{email}</strong>. {nota} "
            "Volvé a Matix y vas a ver tus eventos."
        ),
    ))


@router.post("/sync", response_model=GoogleSyncRead)
async def sincronizar(
    db: Postgrest = Depends(get_db),
) -> dict[str, Any]:
    """Trigger manual del sync. La app llama acá cuando el usuario
    toca 'Sincronizar ahora' o al abrir el calendario."""
    cuenta = await goauth.cuenta_conectada(db)
    if cuenta is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No hay ninguna cuenta de Google conectada.",
        )
    email = cuenta["email"]
    try:
        resumen = await gcal.sincronizar(db, email)
    except RuntimeError as e:
        # Caso típico: refresh_token rechazado (el usuario revocó el
        # acceso desde Google). Le decimos a la app para que muestre
        # 'reconectar'.
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail=str(e)
        ) from e
    return {"email": email, **resumen}


@router.delete("/disconnect", status_code=status.HTTP_204_NO_CONTENT)
async def desconectar(db: Postgrest = Depends(get_db)) -> None:
    """Borra los tokens del cerebro. NO revoca el grant en Google
    — para eso el usuario va a https://myaccount.google.com/permissions.
    Esto solo deja al cerebro sin acceso."""
    cuenta = await goauth.cuenta_conectada(db)
    if cuenta is None:
        return
    await goauth.desconectar(db, cuenta["email"])


def _pagina_resultado(*, ok: bool, mensaje: str) -> str:
    """HTML mínimo para mostrar al usuario tras el callback de
    Google. Sin estilos pesados — solo un mensaje claro y la
    instrucción de volver a la app."""
    color = "#21D07A" if ok else "#FF4D5E"
    titulo = "✓ Listo" if ok else "✗ Algo falló"
    return f"""<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Matix · Google OAuth</title>
  <style>
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #0B0F1A;
      color: #E8ECF4;
      margin: 0;
      padding: 32px 20px;
      display: flex;
      flex-direction: column;
      align-items: center;
      min-height: 100vh;
      box-sizing: border-box;
    }}
    .card {{
      background: #161B2E;
      border: 1px solid rgba(255,255,255,0.06);
      border-radius: 16px;
      padding: 28px 24px;
      max-width: 420px;
      width: 100%;
      margin-top: 60px;
    }}
    .titulo {{
      font-size: 22px;
      font-weight: 700;
      color: {color};
      margin: 0 0 12px;
    }}
    .mensaje {{
      font-size: 15px;
      line-height: 1.5;
      color: #E8ECF4;
      margin: 0 0 20px;
    }}
    .cta {{
      font-size: 13px;
      color: #8A93A8;
      margin: 0;
    }}
  </style>
</head>
<body>
  <div class="card">
    <h1 class="titulo">{titulo}</h1>
    <p class="mensaje">{mensaje}</p>
    <p class="cta">Puedes cerrar esta pestaña y volver a la app.</p>
  </div>
</body>
</html>
"""
