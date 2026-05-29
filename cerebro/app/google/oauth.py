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

# Scopes de Calendar.
#
# Paso 2 reemplazó `calendar.readonly` por `calendar` full (lectura +
# escritura + gestión de calendarios). El usuario reautoriza una vez
# al actualizar a Paso 2 — ver `docs/Plan_Capa4.md` · Scope OAuth.
#
# El campo `email`/`openid` viene "gratis" como parte del consent y
# nos permite identificar la cuenta conectada (PK de oauth_google).
SCOPES_PASO_2 = [
    "https://www.googleapis.com/auth/calendar",
    "openid",
    "https://www.googleapis.com/auth/userinfo.email",
]

# Alias para compatibilidad con código existente que aún referencia
# `SCOPES_PASO_1`. Mantenemos una sola lista de scopes activos.
SCOPES_PASO_1 = SCOPES_PASO_2


# Scope mínimo que tiene que estar presente para que el push
# bidireccional funcione. Si los scopes guardados no lo incluyen,
# la app pinta el banner "Reconectar para sincronización bidireccional".
SCOPE_ESCRITURA_CALENDAR = "https://www.googleapis.com/auth/calendar"


def tiene_escritura_calendar(scopes: list[str] | None) -> bool:
    """True si los scopes guardados incluyen permiso de escritura
    en Calendar. Vale `calendar` (full) o `calendar.events` (más
    granular, por si en el futuro bajamos). Ojo: `calendar.readonly`
    NO alcanza."""
    if not scopes:
        return False
    return any(
        s
        in (
            "https://www.googleapis.com/auth/calendar",
            "https://www.googleapis.com/auth/calendar.events",
        )
        for s in scopes
    )


def _build_flow(state: str | None = None) -> Flow:
    """Arma un `Flow` de google-auth con la config de cliente del
    cerebro (Web application credentials del proyecto Google Cloud).
    El `state` lo usa Google para protegernos de CSRF — lo pasamos
    al hacer la URL y lo verificamos en el callback.

    Importante: en `google-auth-oauthlib >= 1.x`, el `Flow` viene con
    `autogenerate_code_verifier=True` por defecto, así que cada vez
    que se llama a `authorization_url()` se genera un nuevo
    `code_verifier` y se manda el `code_challenge` correspondiente a
    Google. Eso obliga a persistir el verifier entre la generación
    de la URL y el callback (ver `url_de_autorizacion` y
    `completar_autorizacion`).
    """
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


def url_de_autorizacion(state: str) -> tuple[str, str]:
    """Genera la URL de consentimiento y devuelve `(url, code_verifier)`.

    El `code_verifier` del PKCE lo genera el `Flow` automáticamente
    al armar la URL (google-auth-oauthlib lo trae habilitado por
    defecto). Google guarda el `code_challenge` derivado y, en el
    intercambio code→tokens, exige que se mande de vuelta el
    `code_verifier` original. Por eso esta función lo devuelve junto
    con la URL: el router tiene que persistirlo indexado por `state`
    y pasarlo a `completar_autorizacion()` en el callback. Si no, el
    token exchange falla con `invalid_grant: Missing code verifier`.

    Parámetros que pedimos a Google:
    - `access_type='offline'` para que nos dé refresh_token (sin esto,
      solo access_token de 1 hora y nunca más).
    - `prompt='consent'` fuerza la pantalla aunque ya hayamos
      autorizado antes — necesario para garantizar que refresh_token
      venga en la respuesta.
    - `include_granted_scopes='true'` permite incremental consent en
      futuros pasos sin perder scopes previos.
    """
    flow = _build_flow(state=state)
    url, _ = flow.authorization_url(
        access_type="offline",
        prompt="consent",
        include_granted_scopes="true",
    )
    return url, flow.code_verifier


async def completar_autorizacion(
    db: Postgrest, code: str, state: str, code_verifier: str
) -> str:
    """Intercambia el `code` por tokens y los guarda en Supabase.
    Devuelve el email de la cuenta autorizada.

    `code_verifier` es el que generamos al armar la URL — Google lo
    exige para cerrar el PKCE iniciado en la fase de autorización.
    Se lo seteamos al Flow ANTES de `fetch_token` y desactivamos el
    autogenerate para que no nos genere otro distinto.
    """
    flow = _build_flow(state=state)
    flow.code_verifier = code_verifier
    flow.autogenerate_code_verifier = False
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
    scopes = f.get("scopes") or []
    return {
        "email": f["email"],
        "scopes": scopes,
        "tiene_escritura": tiene_escritura_calendar(scopes),
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
