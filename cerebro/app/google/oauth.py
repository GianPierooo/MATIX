"""OAuth de Google (Capa 4 Paso 1).

Toda la negociación con Google + custodia de tokens vive acá.
Otros módulos (ej. `calendar.py`) piden un cliente autenticado a
`obtener_credenciales()` sin tener que pensar en refresh / scopes.

Decisiones documentadas en `docs/Plan_Capa4.md`:
- Sync a Supabase como fuente de verdad.
- Tokens en plaintext, protegidos por RLS de Supabase + service_role.
- Scopes mínimos por paso. Paso 1 = calendar.readonly.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

from google.auth.exceptions import RefreshError
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import Flow

from ..config import settings
from ..db import Postgrest

logger = logging.getLogger("matix.google.oauth")


# Endpoints de Google. URLs estáticas, no las parametrizamos.
_AUTH_URI = "https://accounts.google.com/o/oauth2/auth"
_TOKEN_URI = "https://oauth2.googleapis.com/token"

# Scope del Paso 1: solo lectura del calendario. Si en futuros pasos
# necesitamos más, se suman acá y el usuario re-autoriza.
SCOPES_PASO_1 = [
    "https://www.googleapis.com/auth/calendar.readonly",
    # Estos dos son automáticos cuando se pide algo de Google; los
    # listamos para que el `scope` que devuelva Google incluya el
    # email del usuario, que usamos como clave primaria.
    "openid",
    "https://www.googleapis.com/auth/userinfo.email",
]


def _build_flow(state: str | None = None) -> Flow:
    """Arma un `Flow` de google-auth con la config de cliente del
    cerebro (Web application credentials del proyecto Google Cloud).
    El `state` lo usa Google para protegernos de CSRF — lo pasamos
    al hacer la URL y lo verificamos en el callback."""
    if not (
        settings.google_client_id
        and settings.google_client_secret
        and settings.google_redirect_uri
    ):
        raise RuntimeError(
            "OAuth Google no está configurado en el cerebro: "
            "faltan GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET / "
            "GOOGLE_REDIRECT_URI."
        )
    flow = Flow.from_client_config(
        {
            "web": {
                "client_id": settings.google_client_id,
                "client_secret": settings.google_client_secret,
                "auth_uri": _AUTH_URI,
                "token_uri": _TOKEN_URI,
                "redirect_uris": [settings.google_redirect_uri],
            }
        },
        scopes=SCOPES_PASO_1,
        state=state,
    )
    flow.redirect_uri = settings.google_redirect_uri
    return flow


def url_de_autorizacion(state: str) -> str:
    """Genera la URL a la que la app manda al usuario.

    - `access_type='offline'` para que Google nos dé refresh_token
      (sin esto, solo nos da access_token de 1 hora y nunca más).
    - `prompt='consent'` fuerza que aparezca la pantalla aunque ya
      hayamos autorizado antes — necesario para garantizar que
      refresh_token venga en la respuesta. Sin esto, después de la
      primera vez Google no lo manda.
    - `include_granted_scopes='true'` permite que en pasos futuros,
      cuando sumemos scopes, Google haga el incremental consent
      sin perder los previos.
    """
    flow = _build_flow(state=state)
    url, _ = flow.authorization_url(
        access_type="offline",
        prompt="consent",
        include_granted_scopes="true",
    )
    return url


async def completar_autorizacion(
    db: Postgrest, code: str, state: str
) -> str:
    """Intercambia el `code` por tokens y los guarda en Supabase.
    Devuelve el email de la cuenta autorizada."""
    flow = _build_flow(state=state)
    flow.fetch_token(code=code)
    creds = flow.credentials

    # Sacar el email del id_token (viene con scope openid + email).
    email = _extraer_email(creds)
    if not email:
        raise RuntimeError(
            "Google no devolvió el email del usuario. ¿Faltó scope?"
        )

    expira = creds.expiry  # naive UTC en google-auth
    if expira and expira.tzinfo is None:
        expira = expira.replace(tzinfo=timezone.utc)

    payload = {
        "email": email,
        "access_token": creds.token,
        "refresh_token": creds.refresh_token or "",
        "token_expiry": expira.isoformat() if expira else None,
        "scopes": list(creds.scopes or []),
        "conectado_en": datetime.now(timezone.utc).isoformat(),
    }
    # Upsert via PostgREST — el campo `email` es PK.
    await db._http.post(  # noqa: SLF001
        "/oauth_google",
        json=payload,
        headers={"Prefer": "resolution=merge-duplicates,return=minimal"},
    )
    logger.info("OAuth google completado para %s", email)
    return email


async def obtener_credenciales(
    db: Postgrest, email: str
) -> Credentials | None:
    """Devuelve credenciales válidas (refrescadas si hicieron falta)
    para llamar al Calendar/Tasks/Gmail API. `None` si no hay cuenta
    conectada con ese email."""
    filas = await db.list(
        "oauth_google", filters={"email": email}, limit=1
    )
    if not filas:
        return None
    fila = filas[0]
    expira_str = fila.get("token_expiry")
    expira = (
        datetime.fromisoformat(expira_str.replace("Z", "+00:00"))
        if expira_str
        else None
    )
    creds = Credentials(
        token=fila["access_token"],
        refresh_token=fila["refresh_token"] or None,
        token_uri=_TOKEN_URI,
        client_id=settings.google_client_id,
        client_secret=settings.google_client_secret,
        scopes=fila.get("scopes") or [],
        expiry=expira.replace(tzinfo=None) if expira else None,
    )

    # Si el access_token ya expiró o está por expirar, lo renovamos
    # con el refresh_token. google-auth lo hace todo: solo llamamos
    # a `refresh()`.
    if creds.expired or _expira_pronto(expira):
        try:
            creds.refresh(Request())
        except RefreshError as e:
            logger.warning(
                "Refresh token de %s rechazado por Google: %s. "
                "El usuario tiene que re-autorizar.",
                email,
                e,
            )
            return None
        # Guardar las nuevas credenciales en BD.
        nuevo_expiry = creds.expiry
        if nuevo_expiry and nuevo_expiry.tzinfo is None:
            nuevo_expiry = nuevo_expiry.replace(tzinfo=timezone.utc)
        await db._http.patch(  # noqa: SLF001
            "/oauth_google",
            params={"email": f"eq.{email}"},
            json={
                "access_token": creds.token,
                "token_expiry": (
                    nuevo_expiry.isoformat() if nuevo_expiry else None
                ),
            },
        )
    return creds


async def cuenta_conectada(db: Postgrest) -> dict | None:
    """Resumen para la UI: si hay una cuenta conectada, devuelve
    email + último sync + scopes. Si no, None. La app llama a este
    endpoint para saber si pintar 'Conectar' o 'Conectado · email'."""
    filas = await db.list(
        "oauth_google", order="conectado_en.desc", limit=1
    )
    if not filas:
        return None
    f = filas[0]
    return {
        "email": f["email"],
        "scopes": f.get("scopes") or [],
        "conectado_en": f["conectado_en"],
        "ultimo_sync_en": f.get("ultimo_sync_en"),
    }


async def desconectar(db: Postgrest, email: str) -> bool:
    """Borra los tokens. La app deja de tener acceso al Google del
    usuario. No revoca el grant en Google (para eso el usuario va a
    https://myaccount.google.com/permissions). Devuelve True si
    había algo que borrar."""
    r = await db.delete_where("oauth_google", filters={"email": email})
    return r > 0


async def marcar_sync(db: Postgrest, email: str) -> None:
    """Actualiza el `ultimo_sync_en` tras un sync exitoso."""
    await db._http.patch(  # noqa: SLF001
        "/oauth_google",
        params={"email": f"eq.{email}"},
        json={"ultimo_sync_en": datetime.now(timezone.utc).isoformat()},
    )


# ─── helpers internos ────────────────────────────────────────────────


def _extraer_email(creds: Credentials) -> str | None:
    """Extrae el email del id_token. google-auth ya validó la
    firma al hacer el fetch_token."""
    try:
        from google.oauth2 import id_token
        from google.auth.transport import requests as g_requests

        idinfo = id_token.verify_oauth2_token(
            creds.id_token,
            g_requests.Request(),
            audience=settings.google_client_id,
        )
        return idinfo.get("email")
    except Exception:  # noqa: BLE001
        return None


def _expira_pronto(expira: datetime | None) -> bool:
    """True si el token expira dentro de los próximos 60 segundos."""
    if expira is None:
        return False
    ahora = datetime.now(timezone.utc)
    return expira - ahora < timedelta(seconds=60)
