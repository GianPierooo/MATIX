# Dockerfile del cerebro de Matix (Capa 2 Despliegue).
#
# Imagen slim de Python + uv para builds rápidos. Railway detecta este
# Dockerfile y lo construye sin Nixpacks. Si en el futuro
# quisiéramos volver a Nixpacks, basta con renombrar/borrar este
# archivo y Railway elige automáticamente.

FROM python:3.12-slim

# uv es nuestro gestor de paquetes; lo instalamos del binario oficial
# para no depender de pip-installs lentos.
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Sin .pyc en el contenedor + stdout sin buffer para que los logs de
# Railway sean en tiempo real.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    # uv: instala las deps en /app/.venv para que queden en una
    # capa y se reuse el cache si pyproject.toml no cambió.
    UV_PROJECT_ENVIRONMENT=/app/.venv \
    UV_LINK_MODE=copy

WORKDIR /app

# Primero solo los manifiestos: aprovecha el cache de Docker para
# no reinstalar deps en cada cambio de código.
COPY pyproject.toml uv.lock* ./
RUN uv sync --frozen --no-install-project --no-dev

# Ahora el código.
COPY app ./app

# Termina de "instalar" el proyecto (en modo editable, sin tocar las
# deps que ya están del paso anterior).
RUN uv sync --frozen --no-dev

# Railway pasa el puerto vía $PORT. Lo binding-eamos a 0.0.0.0 para
# que la red del contenedor lo exponga.
EXPOSE 8000
CMD ["sh", "-c", "uv run uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips='*'"]
