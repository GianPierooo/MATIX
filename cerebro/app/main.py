"""Cerebro de Matix · entrypoint FastAPI.

Endurecido para despliegue (Capa 2 Despliegue Fase A):

- **Auth obligatoria** en todos los endpoints salvo `/health`.
- **Rate limit** por IP vía `slowapi` (default global 120 / minuto).
- **Errores limpios**: ninguna respuesta hacia afuera incluye stack
  traces, paths del sistema ni detalles del entorno. Las
  `HTTPException` que levantamos a propósito sí llegan al cliente
  con su mensaje legible.
- **CORS deny-all por defecto**: la app Android es cliente nativo,
  no navegador. Solo si `MATIX_CORS_ORIGINS` está poblado en env se
  habilita el middleware con esa lista.
- **Logging básico** que NO loguea claves ni payloads sensibles.
"""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from slowapi.util import get_remote_address

from .config import settings
from .db import db
from .routers import (
    apuntes,
    categorias,
    cierres_dia,
    cuadernos,
    cursos,
    evaluaciones,
    eventos,
    matix,
    profile,
    proyectos,
    sesiones_clase,
    subtareas,
    tareas,
    version,
)

# ─── Logging ────────────────────────────────────────────────────────
#
# `uvicorn` ya tiene su propia configuración con timestamps. Acá solo
# afinamos el nivel y nos aseguramos de que ningún logger nuestro
# imprima claves. Como política, NUNCA usamos `logger.info(body)` con
# el payload completo — el body puede traer datos personales del
# usuario (apuntes, mensajes de chat). Si necesitamos inspeccionar
# algo, se loguea solo el método+ruta+status.

logger = logging.getLogger("matix.cerebro")
logger.setLevel(logging.INFO)


# ─── Rate limit ─────────────────────────────────────────────────────
#
# Por IP, ventana móvil. Default 120/min cubre con margen el uso
# normal (chat con tools encadena hasta 6 vueltas al modelo por
# mensaje; un humano no genera más de unos pocos por minuto). Los
# routers individuales pueden override-ar este límite si conviene
# — por ahora, todos heredan el global.

limiter = Limiter(
    key_func=get_remote_address,
    default_limits=["120/minute"],
    # `headers_enabled=True` agrega `X-RateLimit-*` al response,
    # útil para debuggear cuotas desde la app sin necesidad de logs.
    headers_enabled=True,
)


@asynccontextmanager
async def lifespan(_: FastAPI):
    logger.info(
        "cerebro arrancando — env=%s, cors_origins=%d",
        settings.matix_env,
        len(settings.cors_origins_list),
    )
    try:
        yield
    finally:
        await db.aclose()


app = FastAPI(
    title="Matix · Cerebro",
    version="0.2.0",
    lifespan=lifespan,
    # Ocultamos la doc en prod — no es secreto pero no hace falta.
    docs_url="/docs" if settings.matix_env != "prod" else None,
    redoc_url="/redoc" if settings.matix_env != "prod" else None,
    openapi_url="/openapi.json" if settings.matix_env != "prod" else None,
)

# Rate limit: hay que pegar el limiter al app y meter el middleware.
app.state.limiter = limiter
app.add_exception_handler(
    RateLimitExceeded, _rate_limit_exceeded_handler  # type: ignore[arg-type]
)
app.add_middleware(SlowAPIMiddleware)


# CORS — deny-all por defecto. Solo si hay orígenes configurados,
# se habilita el middleware con esa whitelist exacta.
if settings.cors_origins_list:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins_list,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PATCH", "DELETE"],
        allow_headers=["Content-Type", "X-Matix-Key"],
        max_age=86400,
    )


# ─── Manejo de errores ──────────────────────────────────────────────
#
# FastAPI por defecto no expone stack traces (eso es buena noticia),
# pero igual queremos:
# - Sanear el detalle de cualquier excepción no esperada — nunca
#   filtrar paths del FS, nombres de módulos internos, etc.
# - Loguear server-side para poder diagnosticar después.


@app.exception_handler(Exception)
async def _no_filtrar_excepciones(request: Request, exc: Exception):
    """Atrapa CUALQUIER excepción no manejada. Loguea con `exc_info`
    pero responde con un mensaje genérico y un id correlación."""
    # `request.state.request_id` lo podríamos llenar con un middleware
    # de tracing más adelante. Por ahora, basta con el log.
    logger.exception("excepción no manejada en %s %s", request.method, request.url.path)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"detail": "Error interno del cerebro."},
    )


# ─── Endpoints ──────────────────────────────────────────────────────


@app.get("/health")
def health() -> dict[str, str]:
    """Único endpoint abierto. Sin auth, sin claves. Devuelve solo
    estado y entorno — útil para healthchecks de Railway/UptimeRobot."""
    return {"status": "ok", "env": settings.matix_env}


for r in (
    profile.router,
    categorias.router,
    cursos.router,
    sesiones_clase.router,
    tareas.router,
    subtareas.router,
    evaluaciones.router,
    eventos.router,
    cuadernos.router,
    apuntes.router,
    proyectos.router,
    cierres_dia.router,
    matix.router,
    version.router,
):
    app.include_router(r, prefix="/api/v1")
