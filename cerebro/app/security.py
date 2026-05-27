"""Autenticación cliente ↔ cerebro vía header `X-Matix-Key`."""
from __future__ import annotations

from fastapi import Header, HTTPException, status

from .config import settings


async def require_api_key(
    x_matix_key: str | None = Header(default=None, alias="X-Matix-Key"),
) -> None:
    expected = settings.matix_api_key
    if not expected or x_matix_key != expected:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="API key inválida",
        )
