# Matix

Asistente personal y centro de mando de la vida — privado.
Hub donde viven tareas, calendario, universidad, apuntes y
proyectos, con una IA (Matix) que ayuda a capturar y gestionar
todo sin fricción.

Este repositorio es privado. Lee `CLAUDE.md` antes de tocar nada;
manda sobre cualquier otra cosa.

## Arquitectura

```
app/        Flutter (Android) — la interfaz del hub
cerebro/    FastAPI (Python)  — la inteligencia y el API
supabase/   PostgreSQL        — la fuente única de verdad
mockups/    Referencia visual de las pantallas
docs/       Mapa del hub, plan por capas y estado
```

La app habla **solo** con el cerebro. El cerebro habla con Supabase
y con OpenAI. Las API keys viven solo en el cerebro — la app porta
una `MATIX_API_KEY` compartida que el cerebro valida en cada
request (`X-Matix-Key`).

## Capa actual

- **Capa 1** — Armazón del hub. ✅
- **Capa 2** — Matix conversacional (chat, voz de entrada, modo
  manos libres, tools sobre todo el hub, medidor de uso, papelera). ✅
- **Capa 2 Despliegue** — Cerebro en la nube (Railway). Ver
  [docs/SETUP_DESPLIEGUE.md](docs/SETUP_DESPLIEGUE.md).

## Cómo arrancar en local

### Cerebro (FastAPI + uv)

```powershell
cd cerebro
copy .env.example .env       # luego rellenar las claves
uv sync
uv run uvicorn app.main:app --reload --port 8000
```

`GET http://localhost:8000/health` debe devolver
`{"status":"ok","env":"dev"}`. Cualquier otro endpoint exige el
header `X-Matix-Key`.

### App (Flutter, Android)

```powershell
cd app
flutter pub get
# Build APK debug apuntando al cerebro local:
flutter build apk --debug `
  --dart-define MATIX_API_URL=http://localhost:8000 `
  --dart-define MATIX_API_KEY=<el de cerebro/.env> `
  --dart-define MATIX_ENV=dev

# Para correr con cable USB + adb reverse:
adb reverse tcp:8000 tcp:8000
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Para instalar el APK release apuntando al cerebro en Railway, ver
[docs/SETUP_DESPLIEGUE.md](docs/SETUP_DESPLIEGUE.md).

### Base de datos

Las migraciones SQL están en `supabase/migrations/`. Se aplican vía
Management API con `SUPABASE_ACCESS_TOKEN` y `SUPABASE_PROJECT_REF`
en `cerebro/.env` (o se pegan en Supabase Studio → SQL Editor).

### Tests

```powershell
# Cerebro (integración real contra Supabase)
cd cerebro
uv run pytest

# App
cd app
flutter analyze
flutter test
```

## Seguridad

- `.env` NUNCA se commitea (ver `.gitignore`).
- `SUPABASE_SERVICE_ROLE_KEY` y `OPENAI_API_KEY` viven solo en el
  cerebro. La app no las conoce ni las necesita.
- La app autentica con `X-Matix-Key`. Endpoints expuestos: solo
  `/health` no exige la key.
- Rate limit por IP (`slowapi`, 120 req/min por defecto).
- En `prod`, `/docs` y `/openapi.json` están deshabilitados.
