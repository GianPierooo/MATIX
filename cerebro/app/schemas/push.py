"""Schemas de push / FCM (Push Capa 1)."""
from __future__ import annotations

from pydantic import BaseModel, Field


class RegistrarTokenRequest(BaseModel):
    """La app manda su token de FCM para que el cerebro pueda enviarle
    push. Re-registrar el mismo token es idempotente (upsert)."""

    token: str = Field(min_length=1)
    plataforma: str = "android"


class RegistrarTokenResponse(BaseModel):
    ok: bool = True


class ProbarPushRequest(BaseModel):
    """Manda un push de prueba. Si `token` viene, va solo a ese; si no, a
    todos los tokens registrados."""

    token: str | None = None
    titulo: str = "Matix"
    cuerpo: str = "Push de prueba. Si ves esto, FCM funciona. 🚀"


class ProbarPushResponse(BaseModel):
    enviados: int
    fallidos: int
    detalle: list[str] = Field(default_factory=list)
