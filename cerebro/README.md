# Cerebro de Matix

API FastAPI que conecta la app Flutter con Supabase. La app **nunca**
habla directamente con Supabase: pasa siempre por aquí. Esto mantiene
el `service_role` fuera del móvil y deja todas las reglas de negocio
en un sitio.

## Requisitos

- Python ≥ 3.12 (probado en 3.14)
- [uv](https://docs.astral.sh/uv/) ≥ 0.5

## Arrancar en local

```powershell
copy .env.example .env
# Editar .env y rellenar SUPABASE_SERVICE_ROLE_KEY y MATIX_API_KEY
uv sync
uv run uvicorn app.main:app --reload --port 8000
```

Sanidad: `GET http://localhost:8000/health` → `{"status":"ok","env":"dev"}`.

## Variables de entorno

| Variable                      | Para qué                              | Obligatoria |
|-------------------------------|---------------------------------------|-------------|
| `SUPABASE_URL`                | URL del proyecto Supabase             | sí          |
| `SUPABASE_SERVICE_ROLE_KEY`   | JWT con permisos de servicio          | sí          |
| `MATIX_API_KEY`               | Token compartido cliente ↔ cerebro    | sí          |
| `SUPABASE_ACCESS_TOKEN`       | Management API (aplicar migraciones)  | no          |
| `SUPABASE_PROJECT_REF`        | Ref del proyecto Supabase             | no          |
| `MATIX_ENV`                   | `dev` / `prod`                        | no (`dev`)  |

`Settings` está configurado con `extra="ignore"` — añadir otra clave
al `.env` no rompe el arranque.

## Estructura

```
app/
  main.py                FastAPI, lifespan, registro de routers
  config.py              pydantic-settings que lee .env
  db.py                  Postgrest (httpx) — list/get/insert/update/delete
  security.py            require_api_key dependency
  routers/               Un archivo por entidad
  schemas/               Pydantic v2 (Create / Update / Read) por entidad
tests/
  conftest.py            client autenticado + fixtures de "padres"
  test_<entidad>.py      Tests de integración real contra Supabase
```

## Patrón para añadir un router CRUD nuevo

1. **Schema** en `app/schemas/<entidad>.py`:
   - `EntidadCreate`, `EntidadUpdate` (todos opcionales), `EntidadRead`
     con `model_config = ConfigDict(from_attributes=True)`.
   - Validar con `Field(min_length=1)`, `Literal[...]`, etc. Pydantic
     devuelve 422 automáticamente.
2. **Router** en `app/routers/<entidad>.py`:
   - `APIRouter(prefix="/<entidad>", tags=["..."], dependencies=[Depends(require_api_key)])`.
   - Endpoints `GET ""`, `GET "/{id}"`, `POST ""` (201), `PATCH "/{id}"`, `DELETE "/{id}"` (204).
   - Para listar usa `db.list(TABLE)`; para CRUD `db.get/insert/update/delete`.
   - 404 cuando `get/update/delete` devuelva `None`.
3. **Registrar** el router en `app/main.py` (importar + añadir al loop
   `for r in (...)`).
4. **Tests** en `tests/test_<entidad>.py`:
   - Imitar `tests/test_tareas.py`.
   - Tests de auth (401), 404, validación (422), CRUD ciclo completo.
   - Cada test limpia las filas que crea con `try/finally`.

Ejemplo limpio: `tareas.py` + `schemas/tareas.py` + `test_tareas.py`.
Ejemplo con reglas de negocio: `proyectos.py` + `test_proyectos.py`
(tope de 3 activos, coherencia acción siguiente ↔ proyecto,
manejo automático de `inactivo_desde` y `ultima_actividad_en`).

## Reglas de negocio en el router, no en la BD

Cuando una regla necesita devolver un mensaje legible al usuario
(ej. tope de 3 proyectos activos), va en el router como 409 con un
`detail` claro. Triggers de Postgres se reservan para invariantes
mecánicas (timestamps `actualizado_en`, integridad referencial).

## El reloj — `ultima_actividad_en` y compañía

Los timestamps que el cerebro va a **comparar entre sí en
operaciones sucesivas** (ej. `ultima_actividad_en` de proyectos) los
asigna el cerebro con `datetime.now(timezone.utc).isoformat()`, no
se delegan al `default now()` de Postgres. Razón: el reloj de la PC
y el del servidor Supabase pueden discrepar y la comparación de
strings ISO 8601 puede salir "al revés". `creado_en` y
`actualizado_en` siguen viniendo de Postgres porque nadie los
compara con timestamps del cerebro.

## Migraciones

Viven en `supabase/migrations/*.sql`. Aplicadas hasta ahora:

| Archivo                       | Qué hace                              |
|-------------------------------|---------------------------------------|
| `0001_initial_schema.sql`     | 10 tablas iniciales + triggers + RLS  |
| `0002_proyectos.sql`          | Tabla `proyectos` + FK `proyecto_id` en `tareas`, `apuntes`, `eventos` |

Aplicar nueva migración vía Management API (mismo canal que se usó
para 0001 y 0002):

```python
import httpx, os
token = os.environ["SUPABASE_ACCESS_TOKEN"]
ref = os.environ["SUPABASE_PROJECT_REF"]
sql = open("supabase/migrations/000X_xxx.sql").read()
r = httpx.post(
    f"https://api.supabase.com/v1/projects/{ref}/database/query",
    headers={"Authorization": f"Bearer {token}"},
    json={"query": sql},
)
print(r.status_code, r.text[:500])
```

201 con `[]` = OK (es el patrón de DDL exitoso). El token se obtiene
en `https://supabase.com/dashboard/account/tokens`. La DB password
de Supabase **no** hace falta por este canal.

## Tests

```powershell
cd cerebro
uv run pytest              # toda la suite (42/42 a 2026-05-25)
uv run pytest -v -k tope   # solo los que matchean "tope"
```

Los tests son de **integración real**: hablan con la Supabase del
`.env`, no hay mocks. Justificación: validan el esquema, los
triggers y el comportamiento de PostgREST sin ilusiones.

Si dos tests se solapan creando filas con cuota (p.ej. tope de 3
activos en proyectos), pueden chocar; cada test usa `try/finally`
para limpiar lo suyo, y los "delicados" aparcan los pre-existentes
con un helper (`_aparcar_originales` en `test_proyectos.py`) y los
restauran al final.
