# Dockerfile del cerebro de Matix (Capa 2 Despliegue).
#
# Usamos la imagen oficial de Astral que ya trae `uv` y Python 3.12.
# Más simple que multi-stage con COPY --from, y se actualiza solo si
# bumpeamos la versión de Python aquí.
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    # uv: copy en vez de symlink para que el venv funcione bien
    # cuando Docker monta capas (el default symlink puede romper si
    # el cache de uv está en otra capa).
    UV_LINK_MODE=copy \
    # Compila .pyc al instalar — startup más rápido del contenedor.
    UV_COMPILE_BYTECODE=1

WORKDIR /app

# Capa de deps: cambia solo cuando pyproject.toml / uv.lock cambian.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project --no-dev

# Capa de código.
COPY app ./app

# Railway pasa el puerto vía $PORT. Bindeamos a 0.0.0.0 y
# habilitamos --proxy-headers porque Railway corre detrás de un
# proxy: sin esto, todas las IPs se ven como 127.0.0.1 y el rate
# limit por IP no funciona.
EXPOSE 8000
CMD ["sh", "-c", "uv run --no-dev uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips=*"]
