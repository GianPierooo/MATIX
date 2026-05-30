"""Envío de push vía Firebase Cloud Messaging (Push Capa 1).

Aislado como el único módulo que importa `firebase_admin`. Se inicializa
de forma lazy con el service account de Firebase, que llega como JSON
completo en la variable de entorno `FIREBASE_SERVICE_ACCOUNT_JSON`
(Railway). Si falta, lanza `RuntimeError` con mensaje claro y el router
lo traduce a 503.

Capa 1: solo `enviar_push(token, …)`. El scheduler y la migración de los
recordatorios reales son capas siguientes.
"""
from __future__ import annotations

import json
import threading

from ..config import settings

# `firebase_admin.initialize_app` solo puede llamarse una vez por proceso;
# protegemos la inicialización con un lock.
_lock = threading.Lock()
_app = None


def _ensure_app():
    """Inicializa (una sola vez) la app de firebase_admin con el service
    account del entorno. Devuelve la app. Lanza RuntimeError si no está
    configurada o el JSON es inválido."""
    global _app
    if _app is not None:
        return _app
    with _lock:
        if _app is not None:
            return _app
        raw = settings.firebase_service_account_json.strip()
        if not raw:
            raise RuntimeError(
                "FIREBASE_SERVICE_ACCOUNT_JSON no está configurada en el "
                "cerebro (Railway). Sin ella no se puede mandar push."
            )
        try:
            datos = json.loads(raw)
        except json.JSONDecodeError as e:
            raise RuntimeError(
                "FIREBASE_SERVICE_ACCOUNT_JSON no es un JSON válido."
            ) from e

        # Import perezoso: firebase_admin es pesado; solo se carga si de
        # verdad vamos a mandar push.
        import firebase_admin
        from firebase_admin import credentials

        cred = credentials.Certificate(datos)
        _app = firebase_admin.initialize_app(cred)
        return _app


class TokenInvalido(Exception):
    """El token ya no es válido (desinstalado/expirado): hay que borrarlo."""


def enviar_push(
    token: str,
    *,
    titulo: str,
    cuerpo: str,
    data: dict[str, str] | None = None,
) -> str:
    """Manda un push a un token. Devuelve el message id de FCM.

    `data` viaja como datos (ej. `{"payload": "evento:<id>"}`) para el deep
    link: la app lo lee al tocar la notificación y abre el evento/tarea.

    Es **bloqueante** (firebase_admin usa requests por debajo): el caller
    lo corre en un thread aparte con `asyncio.to_thread` para no bloquear
    el event loop. Si el token es inválido, lanza [TokenInvalido].
    """
    _ensure_app()
    from firebase_admin import messaging

    mensaje = messaging.Message(
        notification=messaging.Notification(title=titulo, body=cuerpo),
        token=token,
        data=data or {},
        android=messaging.AndroidConfig(
            priority="high",
            notification=messaging.AndroidNotification(
                channel_id="matix_recordatorios",
            ),
        ),
    )
    try:
        return messaging.send(mensaje)
    except messaging.UnregisteredError as e:  # token muerto
        raise TokenInvalido(str(e)) from e
