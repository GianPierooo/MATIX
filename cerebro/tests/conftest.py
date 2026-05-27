"""Fixtures comunes para los tests del cerebro.

Los tests son de integración: hablan con una Supabase real (no
mocks). La idea es validar el esquema y los endpoints contra
Postgres de verdad.

**Selección de Supabase (Capa 2 Paso 5.1)**

Si existe `cerebro/.env.test` con `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY`
de un proyecto separado, los tests usan ESE proyecto. Si no existe,
caen al `.env` normal — el del seed/dev del usuario — y se apoyan
en las redes de seguridad (prefijos `_test_…` + fixture session-level
de barrido). Ver `docs/Plan_Capa2.md` y `cerebro/.env.test.example`.

La carga del .env.test pasa ANTES de importar `app.config` para que
`Settings()` lea los env vars correctos. Pydantic-Settings respeta
env vars sobre los valores del dotenv, así que con `override=True`
en `load_dotenv` los valores ganan limpio.

**Aislamiento**

- Toda fila creada por una fixture se purga con `/permanente`, no con
  el DELETE normal (que es SOFT desde Paso 5). Así no se llena la
  papelera del proyecto-test.
- Una fixture autouse `_barrer_residuos_test` a nivel session corre
  DESPUÉS de todos los tests y borra cualquier fila cuyo título/nombre
  empiece con `_test_` / `test_`. Red de seguridad por si un test
  crashea antes de su `finally`.

Nota técnica: pytest-asyncio crea un event loop nuevo por test, así
que se inyecta un `Postgrest` fresco por test vía
`app.dependency_overrides[get_db]`. El singleton del módulo nunca
abre conexiones durante los tests.
"""
from __future__ import annotations

import os
from collections.abc import AsyncIterator
from pathlib import Path

# IMPORTANTE: cargar `.env.test` ANTES de importar la app. Si lo
# cargamos después, `app.config.Settings()` ya leyó el `.env` normal
# y no hay vuelta atrás.
from dotenv import load_dotenv

_ENV_TEST = Path(__file__).resolve().parent.parent / ".env.test"
USANDO_ENV_TEST = _ENV_TEST.exists()
if USANDO_ENV_TEST:
    load_dotenv(_ENV_TEST, override=True)

import httpx  # noqa: E402
import pytest  # noqa: E402
import pytest_asyncio  # noqa: E402
from httpx import ASGITransport, AsyncClient  # noqa: E402

from app.config import settings  # noqa: E402
from app.db import Postgrest, get_db  # noqa: E402
from app.main import app  # noqa: E402


def pytest_report_header(config: object) -> str:  # noqa: ARG001
    """Imprime una línea al inicio del run aclarando contra qué
    Supabase corren los tests. Ayuda a evitar sorpresas."""
    if USANDO_ENV_TEST:
        return f"supabase para tests: {settings.supabase_url} (.env.test)"
    return (
        f"supabase para tests: {settings.supabase_url} (.env real, sin "
        ".env.test — ver docs/Plan_Capa2.md)"
    )


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
        """
    )
