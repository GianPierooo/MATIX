# Cómo correr Matix desde cero

Guía completa para levantar Matix en una PC nueva o tras un wipe.
Pasos en orden — si algo falla, vuelve al paso anterior antes de
seguir.

---

## 1. Requisitos del sistema

| Componente            | Versión mínima | Comprobar con                |
|-----------------------|----------------|------------------------------|
| Windows               | 10 / 11        | `winver`                     |
| Python                | 3.12+          | `python --version`           |
| uv                    | 0.5+           | `uv --version`               |
| Flutter               | 3.41+          | `flutter --version`          |
| Android SDK           | API 34+        | `flutter doctor`             |
| Git                   | cualquiera     | `git --version`              |

Si `flutter doctor` no está todo en verde, arregla eso primero.

---

## 2. Clonar el repo

```powershell
git clone <url> matix
cd matix
```

---

## 3. Configurar el cerebro

```powershell
cd cerebro
copy .env.example .env
```

Edita `cerebro/.env` con tus valores reales:

```env
SUPABASE_URL=https://<tu-ref>.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<service_role JWT de Supabase>
SUPABASE_ACCESS_TOKEN=<sbp_... de Account > Access Tokens>
SUPABASE_PROJECT_REF=<tu-ref>
MATIX_API_KEY=<token largo aleatorio, p.ej. openssl rand -base64 48>
MATIX_ENV=dev
```

> Nunca commitees `.env`. Está en `.gitignore`.

Instala dependencias:

```powershell
uv sync
```

---

## 4. Aplicar migraciones a Supabase

Las migraciones SQL están en `supabase/migrations/`. Aplicar **en orden**
con la Management API:

```powershell
cd ..\cerebro
python -c "import httpx, os; from dotenv import load_dotenv; load_dotenv('.env'); ^
  sql = open('../supabase/migrations/0001_initial_schema.sql', 'r', encoding='utf-8').read(); ^
  r = httpx.post(f'https://api.supabase.com/v1/projects/{os.environ[\"SUPABASE_PROJECT_REF\"]}/database/query', ^
    headers={'Authorization': f'Bearer {os.environ[\"SUPABASE_ACCESS_TOKEN\"]}'}, ^
    json={'query': sql}, timeout=60); ^
  print(r.status_code, r.text[:300])"
```

Repite para `0002_proyectos.sql` y `0003_cierres_dia.sql`. Cada uno
debe devolver `201 []`.

(Alternativa: pegar cada SQL en Supabase Studio → SQL Editor → Run.)

---

## 5. Arrancar el cerebro

```powershell
cd cerebro
uv run uvicorn app.main:app --reload --port 8000
```

Sanidad: en otra terminal,

```powershell
curl http://localhost:8000/health
```

Debe responder `{"status":"ok","env":"dev"}`.

---

## 6. (Opcional) Pre-cargar datos demo

Con el cerebro arrancado:

```powershell
cd cerebro
$env:PYTHONIOENCODING="utf-8"
uv run python scripts/seed_demo.py
```

Esto carga los 7 cursos universitarios, el horario semanal y los
3 proyectos activos + 3 aparcados del Documento Maestro. Idempotente.

---

## 7. Configurar la app Flutter

```powershell
cd app
flutter pub get
```

---

## 8. Correr la app

### Opción A — Emulador Android Studio

```powershell
flutter emulators --launch Pixel_9
flutter run -d emulator-5554 ^
  --dart-define=MATIX_API_URL=http://10.0.2.2:8000 ^
  --dart-define=MATIX_API_KEY=<el mismo de cerebro/.env> ^
  --dart-define=MATIX_ENV=dev
```

`10.0.2.2` es la dirección del host visto desde el emulador.

### Opción B — Teléfono físico por USB

1. Activa "Depuración por USB" en tu Android (Ajustes → Opciones de
   desarrollador).
2. Conecta el teléfono y autoriza la huella RSA en el popup.
3. Verifica con `adb devices` (debe aparecer como `device`).
4. Hace el **reenvío de puerto** para que `localhost:8000` del
   teléfono apunte al cerebro de la PC:

```powershell
adb reverse tcp:8000 tcp:8000
```

5. Arranca la app:

```powershell
flutter run -d <device-id> ^
  --dart-define=MATIX_API_URL=http://localhost:8000 ^
  --dart-define=MATIX_API_KEY=<el mismo de cerebro/.env> ^
  --dart-define=MATIX_ENV=dev
```

### Opción C — Build APK e instalar manualmente

```powershell
flutter build apk --debug ^
  --dart-define=MATIX_API_URL=http://localhost:8000 ^
  --dart-define=MATIX_API_KEY=<el mismo de cerebro/.env> ^
  --dart-define=MATIX_ENV=dev

adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

---

## 9. Validar que todo funciona

Con la app abierta:

- [ ] La pantalla Inicio dice "Buenos días, Gian Piero" y carga sin
      error de conexión.
- [ ] Pestaña Proyectos muestra los 3 activos (Matix, OnExotic,
      Shadows Games) si corriste el seed.
- [ ] Pestaña Universidad muestra 7 cursos. Al tocar uno, ves su
      horario semanal.
- [ ] Pestaña Tareas: el FAB "+ Nueva tarea" funciona. Al crear una
      con `recordar_en`, te pide permiso de notificaciones la primera
      vez.
- [ ] Calendario: las clases del día aparecen con badge SEMANAL.
- [ ] Icono luna en Inicio → Cierre del día.
- [ ] Icono lupa en Inicio → Búsqueda global.
- [ ] Icono engranaje → Ajustes (toggle "Recordarme el cierre del día").

---

## 10. Tests

Backend:

```powershell
cd cerebro
uv run pytest
```

App:

```powershell
cd app
flutter analyze
flutter test
```

A la fecha de cierre de Capa 1: **46/46 pytest verde · 19/19 flutter
test verde · analyze sin issues**.

---

## Solución de problemas

| Síntoma                                          | Probable causa / fix                                                                                  |
|--------------------------------------------------|-------------------------------------------------------------------------------------------------------|
| `/health` no responde                            | El cerebro no está arrancado. `uv run uvicorn app.main:app --reload`.                                 |
| App muestra "Sin respuesta del cerebro"          | URL mal: si emulador usa `10.0.2.2:8000`; si USB usa `localhost` con `adb reverse`; si Wi-Fi LAN usa IP del PC. |
| Notificaciones no llegan en Huawei               | Ajustes Android → Apps → Matix → Notificaciones → permitir. Y Batería → "Apertura de apps" → Matix → Gestión manual → activar todo. |
| `Gradle daemon disappeared`                       | OOM. Bajar heap en `app/android/gradle.properties` → `-Xmx2G`.                                        |
| Tests del cerebro fallan por "tope 3 activos"    | BD con proyectos activos pre-existentes. Aparca los pre-existentes o limpia la BD.                    |
| `LocaleDataException`                            | Falta `initializeDateFormatting('es', null)` antes de `runApp`. Ya está en `main.dart`.               |
| `SocketException: Operation not permitted (errno=1)` en APK release | Causa A: falta `INTERNET` permission en `app/android/app/src/main/AndroidManifest.xml`. Flutter solo lo añade en debug. Causa B: cleartext HTTP bloqueado a localhost — necesita `res/xml/network_security_config.xml`. **Ambos ya están en el repo**, pero si lo olvidas al hacer una APK nueva, la release fallará en silencio. |

---

## Configuración recomendada del teléfono (Huawei)

1. **Permitir instalación de fuentes desconocidas** (solo para
   instalar APK debug; quitar después).
2. **Notificaciones permitidas** para Matix.
3. **Batería → Apertura de apps → Matix → Gestión manual** con todos
   los toggles activos. Sin esto, EMUI mata las alarmas en background
   y los recordatorios no disparan.
4. **Conexión USB en modo MTP** (no solo carga) para que ADB la vea.

---

## Lo que esta guía NO cubre

- Configurar Supabase desde cero (cuenta, proyecto, etc.) — eso es
  trabajo de una sola vez fuera del repo.
- Capa 2+ (chat con Claude, voz, RAG). Ver `docs/Plan_Capa2.md`
  cuando llegue ese momento.
- Rotación de credenciales (apuntada en `docs/REVISION_PENDIENTE.md`).
