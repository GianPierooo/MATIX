"""Fixtures comunes para los tests del cerebro.

Los tests son de integración: hablan con una Supabase real (no
mocks). La idea es validar el esquema y los endpoints contra
Postgres de verdad.

**Aislamiento duro: NUNCA se toca el Supabase de producción**

El suite SOLO corre si existe `cerebro/.env.test` apuntando a un
proyecto Supabase APARTE (no el de dev/prod). Si falta, abortamos con
instrucciones — antes caíamos al `.env` real en silencio, y eso era el
riesgo: un `pytest` distraído escribía sobre datos de verdad.

Tres redes, de fuera hacia dentro:

1. Sin `cerebro/.env.test` → `pytest.exit` con los pasos de setup.
2. Si `.env.test` apunta a la MISMA `SUPABASE_URL` que `.env` (prod) →
   `pytest.exit`. Imposible escribir en prod aunque te equivoques de URL.
3. Si `MATIX_ENV` cargado no es `test` → `pytest.exit`.

La carga del `.env.test` pasa ANTES de importar `app.config` para que
`Settings()` lea los env vars correctos. Pydantic-Settings respeta los
env vars sobre los valores del dotenv, así que con `override=True` en
`load_dotenv` ganan limpio. Ver `cerebro/.env.test.example`.

**Repetibilidad**

- Toda fila creada por una fixture se purga con `/permanente`, no con
  el DELETE normal (que es SOFT desde Paso 5). Así no se llena la
  papelera del proyecto-test.
- Una fixture autouse `_barrer_residuos_test` a nivel session corre
  DESPUÉS de todos los tests y borra cualquier fila cuyo título/nombre
  empiece con `_test_` / `test_`. Red de seguridad por si un test
  crashea antes de su `finally`. El estado queda limpio entre corridas.

Nota técnica: pytest-asyncio crea un event loop nuevo por test, así
que se inyecta un `Postgrest` fresco por test vía
`app.dependency_overrides[get_db]`. El singleton del módulo nunca
abre conexiones durante los tests.
"""
from __future__ import annotations

import os
from collections.abc import AsyncIterator
from pathlib import Path

import pytest

# IMPORTANTE: cargar `.env.test` ANTES de importar la app. Si lo
# cargamos después, `app.config.Settings()` ya leyó el `.env` normal
# y no hay vuelta atrás.
from dotenv import load_dotenv

_CEREBRO = Path(__file__).resolve().parent.parent
_ENV_TEST = _CEREBRO / ".env.test"
_ENV_PROD = _CEREBRO / ".env"


def _url_supabase_en(ruta: Path) -> str | None:
    """Lee `SUPABASE_URL` de un archivo .env SIN cargarlo al entorno.
    Sirve para comparar test vs prod sin contaminar `os.environ`."""
    if not ruta.exists():
        return None
    for linea in ruta.read_text(encoding="utf-8").splitlines():
        s = linea.strip()
        if s.startswith("#") or "=" not in s:
            continue
        clave, valor = s.split("=", 1)
        if clave.strip().upper() == "SUPABASE_URL":
            return valor.strip().strip('"').strip("'")
    return None


# ─── Guarda 1: sin `.env.test` no se corre (nunca caemos a prod) ──────
if not _ENV_TEST.exists():
    pytest.exit(
        "\n\n  [x] No existe cerebro/.env.test — el suite NO corre contra prod.\n"
        "      Crea un proyecto Supabase de test aparte y copia\n"
        "      cerebro/.env.test.example a cerebro/.env.test con sus\n"
        "      credenciales. Los pasos están dentro de ese .example.\n",
        returncode=2,
    )

# ─── Guarda 2: `.env.test` no puede apuntar al mismo Supabase que prod ─
_URL_PROD = _url_supabase_en(_ENV_PROD)
_URL_TEST = _url_supabase_en(_ENV_TEST)
if _URL_PROD and _URL_TEST and _URL_PROD == _URL_TEST:
    pytest.exit(
        "\n\n  [x] cerebro/.env.test apunta al MISMO Supabase que .env (prod).\n"
        "      Apúntalo a un proyecto de test APARTE. Abortando para no\n"
        "      escribir en producción.\n",
        returncode=2,
    )

load_dotenv(_ENV_TEST, override=True)

import httpx  # noqa: E402
import pytest_asyncio  # noqa: E402
from httpx import ASGITransport, AsyncClient  # noqa: E402

from app.config import settings  # noqa: E402
from app.db import Postgrest, get_db  # noqa: E402
from app.main import app  # noqa: E402

# ─── Guarda 3: el modo declarado debe ser 'test' ──────────────────────
if settings.matix_env != "test":
    pytest.exit(
        f"\n\n  [x] MATIX_ENV no es 'test' (lee '{settings.matix_env}').\n"
        "      Pon MATIX_ENV=test en cerebro/.env.test.\n",
        returncode=2,
    )


def pytest_report_header(config: object) -> str:  # noqa: ARG001
    """Imprime una línea al inicio del run aclarando contra qué
    Supabase corren los tests. Ayuda a evitar sorpresas."""
    return f"supabase para tests: {settings.supabase_url} (.env.test · MATIX_ENV=test)"


@pytest_asyncio.fixture
async def _fresh_db() -> AsyncIterator[Postgrest]:
    pg = Postgrest()
    app.dependency_overrides[get_db] = lambda: pg
    try:
        yield pg
    finally:
        await pg.aclose()
        app.dependency_overrides.pop(get_db, None)


@pytest_asyncio.fixture
async def client(_fresh_db: Postgrest) -> AsyncIterator[AsyncClient]:
    """Cliente HTTP autenticado contra la app en proceso."""
    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport,
        base_url="http://test",
        headers={"X-Matix-Key": settings.matix_api_key},
    ) as c:
        yield c


@pytest_asyncio.fixture
async def client_anon(_fresh_db: Postgrest) -> AsyncIterator[AsyncClient]:
    """Cliente HTTP sin el header `X-Matix-Key` (para probar 401)."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


# ---------- Fixtures de "padres" para tests con foreign keys ----------
#
# Las que apuntan a tablas con borrado SUAVE (tareas/eventos/apuntes)
# limpian con `/permanente` para no dejar residuos en la papelera.


@pytest_asyncio.fixture
async def curso_id(client: AsyncClient) -> AsyncIterator[str]:
    r = await client.post("/api/v1/cursos", json={"nombre": "_test_curso_fix"})
    assert r.status_code == 201, r.text
    cid = r.json()["id"]
    try:
        yield cid
    finally:
        await client.delete(f"/api/v1/cursos/{cid}")


@pytest_asyncio.fixture
async def tarea_id(client: AsyncClient) -> AsyncIterator[str]:
    r = await client.post("/api/v1/tareas", json={"titulo": "_test_tarea_fix"})
    assert r.status_code == 201, r.text
    tid = r.json()["id"]
    try:
        yield tid
    finally:
        # /permanente: la fixture no quiere dejar nada en la papelera.
        await client.delete(f"/api/v1/tareas/{tid}/permanente")


@pytest_asyncio.fixture
async def cuaderno_id(client: AsyncClient) -> AsyncIterator[str]:
    r = await client.post("/api/v1/cuadernos", json={"nombre": "_test_cuaderno_fix"})
    assert r.status_code == 201, r.text
    cid = r.json()["id"]
    try:
        yield cid
    finally:
        await client.delete(f"/api/v1/cuadernos/{cid}")


# ─── Red de seguridad: barrido session-level ─────────────────────────


def _barrer_via_supabase(sql: str) -> None:
    """Ejecuta SQL crudo vía la Management API de Supabase. Solo se
    usa para limpieza de tests — los tests normales hablan por el
    router HTTP."""
    ref = os.environ.get("SUPABASE_PROJECT_REF")
    token = os.environ.get("SUPABASE_ACCESS_TOKEN")
    if not ref or not token:
        # En CI o entornos sin credenciales admin, no rompemos; el
        # barrido es best-effort.
        return
    try:
        httpx.post(
            f"https://api.supabase.com/v1/projects/{ref}/database/query",
            headers={"Authorization": f"Bearer {token}"},
            json={"query": sql},
            timeout=30.0,
        )
    except Exception:
        # No queremos que un error de red al cerrar la session haga
        # fallar el suite entero. Silenciamos.
        pass


@pytest.fixture(scope="session", autouse=True)
def _barrer_residuos_test() -> object:
    """Después de todos los tests, borra cualquier fila cuyo
    título/nombre empiece con `_test_` o `test_` y la fecha del
    cierre de prueba (`1990-01-02`, usada por un test del cierre).

    Es una red — los tests bien escritos limpian solos. Pero si
    crashean antes del finally, esto lo agarra.
    """
    yield
    _barrer_via_supabase(
        """
        DELETE FROM tareas
          WHERE titulo ILIKE 'test%' OR titulo ILIKE '\\_test\\_%';
        DELETE FROM eventos
          WHERE titulo ILIKE 'test%' OR titulo ILIKE '\\_test\\_%';
        DELETE FROM apuntes
          WHERE titulo ILIKE 'test%' OR titulo ILIKE '\\_test\\_%';
        DELETE FROM proyectos
          WHERE nombre ILIKE 'test%' OR nombre ILIKE '\\_test\\_%';
        DELETE FROM cursos
          WHERE nombre ILIKE 'test%' OR nombre ILIKE '\\_test\\_%';
        DELETE FROM cuadernos
          WHERE nombre ILIKE 'test%' OR nombre ILIKE '\\_test\\_%';
        DELETE FROM categorias
          WHERE nombre ILIKE 'test%' OR nombre ILIKE '\\_test\\_%';
        DELETE FROM evaluaciones
          WHERE titulo ILIKE 'test%' OR titulo ILIKE '\\_test\\_%';
        DELETE FROM cierres_dia WHERE fecha < '2000-01-01';
        DELETE FROM device_tokens WHERE token ILIKE '\\_test\\_%';
        """
    )
