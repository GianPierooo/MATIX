# Despliegue del cerebro en Railway

Guía paso a paso de la **Fase B**: subir el repo a GitHub, levantar
el cerebro en Railway, rotar las claves viejas, y compilar el APK
release para usar Matix desde datos móviles sin `adb reverse`.

Tiempo estimado: 30–45 min, casi todo esperando builds.

> **Antes de arrancar** — ¿qué dejó listo la Fase A?
>
> - `.gitignore` ya excluye `.env*`, `*.jks`, `*.key`, screenshots, builds.
> - `cerebro/Dockerfile` + `railway.json` listos.
> - Cerebro endurecido: rate limit, errores limpios, CORS deny-all,
>   `/docs` apagado en `prod`.
> - Una `MATIX_API_KEY` nueva (32+ bytes random) ya en `cerebro/.env`.
> - Los tests pasan: 105 en cerebro, 24 en app.

---

## 1. Repo en GitHub

### 1.1 Inicializar el repo local

Desde la raíz del proyecto (`MATIX/`):

```powershell
git init
git add .
git status   # verificá que NO aparezcan archivos .env ni keys
git commit -m "Matix · Capa 2 lista para despliegue"
```

Si `git status` lista cualquier `.env`, `*.key`, `*.jks` o
`MATIX_API_KEY=...` en algún archivo no-example, **paralo todo** y
revisá `.gitignore` antes de continuar.

### 1.2 Crear el repo en GitHub

1. Abrí https://github.com/new.
2. **Name**: `matix` (o lo que prefieras).
3. **Privado** (importante — el `CLAUDE.md` y demás docs no son para
   el público).
4. **No** tildes "Add README" ni .gitignore ni license — ya los tenés
   locales.
5. Crealo.

### 1.3 Conectar y empujar

GitHub te muestra las instrucciones para "an existing repository".
Copialas; en general son:

```powershell
git branch -M main
git remote add origin https://github.com/<tu-usuario>/matix.git
git push -u origin main
```

---

## 2. Railway: cuenta y proyecto

### 2.1 Cuenta

1. https://railway.app → **Login** → con tu GitHub.
2. La cuenta gratuita ("Trial") sirve para empezar: $5 USD de crédito
   y deploys públicos. Si más adelante querés que no se duerma, pasá
   a Hobby ($5/mes).

### 2.2 Nuevo proyecto desde GitHub

1. Dashboard → **+ New Project** → **Deploy from GitHub repo**.
2. Si es la primera vez, Railway pide instalar su GitHub App;
   acepta y selecciona solo el repo `matix` (no le des acceso global).
3. Elegí el repo `matix`. Railway lee `railway.json` de la raíz,
   ve `cerebro/Dockerfile`, y empieza a buildear.
4. El primer build dura ~3–5 min. Si falla, mirá los logs en la
   pestaña **Deployments**; el error más común es algún typo de env
   var (paso 3).

### 2.3 Healthcheck

`railway.json` ya dice que el healthcheck es `GET /health`. Railway
lo va a probar tras cada deploy. Si Railway dice **"healthy"**, el
contenedor arrancó bien — esto NO significa que el cerebro pueda
llegar a Supabase u OpenAI; eso lo validamos en el paso 5.

---

## 3. Variables de entorno

En Railway → tu servicio → **Variables**. Agregá una por una.

| Variable | De dónde sale | Notas |
|----------|---------------|-------|
| `SUPABASE_URL` | Tu `cerebro/.env` local. Es `https://<ref>.supabase.co` | Idem que en local |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase Dashboard → tu proyecto → Settings → API → `service_role` `secret` | **REGENERAR** ahora (paso 4) |
| `SUPABASE_ACCESS_TOKEN` | (Opcional) Solo si querés aplicar migraciones desde el cerebro en la nube. Para uso normal, dejala vacía. | Opcional |
| `SUPABASE_PROJECT_REF` | El subdominio de tu Supabase URL (sin `.supabase.co`) | Opcional sin el anterior |
| `MATIX_API_KEY` | Tu `cerebro/.env` local — la NUEVA que generó la Fase A | Esa misma irá al APK release |
| `MATIX_ENV` | `prod` | Apaga `/docs`, `/redoc`, `/openapi.json` |
| `OPENAI_API_KEY` | OpenAI Dashboard → API Keys | **REGENERAR** ahora (paso 4) |
| `MATIX_CORS_ORIGINS` | Vacío | No necesitamos CORS — la app Android es cliente nativo |

Después de agregar todas, Railway hace un redeploy automático. Si
no, tocá **Redeploy** manualmente.

### 3.1 Dominio público

En Railway → tu servicio → **Settings** → **Networking** → **Generate
Domain**. Te da algo tipo `matix-cerebro-production.up.railway.app`.

Anotalo — va al APK release en el paso 6.

---

## 4. Rotar las claves viejas

> **Por qué ahora**: durante el desarrollo, las claves del seed
> aparecieron en chats, logs y bash history. La Fase A ya rotó la
> `MATIX_API_KEY` (genera una nueva con `python -c "import secrets;
> print(secrets.token_urlsafe(48))"`). Falta revocar y regenerar el
> resto **antes** de exponer el cerebro a internet.

Hacelo en este orden para evitar cortes:

### 4.1 OpenAI

1. https://platform.openai.com/api-keys
2. Buscá la key que arranca con `sk-proj-_d8wRHX...` (la del seed).
   **Revoke** (icono basurero).
3. Botón **+ Create new secret key** → nombre `matix-cerebro-prod`
   → copiala (no la vas a volver a ver).
4. En Railway → Variables → editá `OPENAI_API_KEY` con la nueva.
5. En tu `cerebro/.env` local **también** pegá la nueva (para
   seguir desarrollando en local con la misma key).

### 4.2 Supabase service_role

1. Supabase Dashboard → tu proyecto → **Settings** → **API**.
2. Busca **service_role** → **Reset secret**.
3. Confirmá. Te da una nueva key (`eyJ...`).
4. En Railway → Variables → editá `SUPABASE_SERVICE_ROLE_KEY`.
5. En tu `cerebro/.env` local también.
6. **Ojo**: cualquier otro proceso que esté usando la key vieja
   (un script seed que dejaste corriendo, un Postgrest abierto) va
   a empezar a fallar. Si reiniciás el cerebro local, listo.

### 4.3 Supabase access token (Management API)

Solo si lo usás para migraciones desde scripts. Si lo usás:

1. Supabase Dashboard → **Account** (esquina sup. der.) → **Access
   Tokens**.
2. Revocá el viejo (`sbp_4fa97...`).
3. Generá uno nuevo `matix-management`.
4. Reemplazá en `cerebro/.env` local. En Railway dejalo vacío si no
   vas a aplicar migraciones desde la nube.

### 4.4 Confirmación

Después de rotar, en local:

```powershell
cd cerebro
uv run uvicorn app.main:app --reload --port 8000
# en otra terminal:
curl -s http://localhost:8000/health   # 200
curl -s -H "X-Matix-Key: <la nueva MATIX_API_KEY>" http://localhost:8000/api/v1/matix/uso   # 200
```

Si los dos responden 200, el rotado está OK localmente. Reiniciá
Railway (Redeploy) por las dudas para que tome las nuevas vars.

---

## 5. Smoke test del cerebro en Railway

Una vez con el dominio del paso 3.1 y todas las vars cargadas:

```powershell
$URL = "https://<tu-dominio>.up.railway.app"
$KEY = "<la NUEVA MATIX_API_KEY>"

# 1. Health abierto, debe ser 200
curl.exe -s -o NUL -w "health: %{http_code}`n" "$URL/health"

# 2. Sin key, debe ser 401
curl.exe -s -o NUL -w "sin key: %{http_code}`n" "$URL/api/v1/matix/uso"

# 3. Con key, debe ser 200
curl.exe -s -H "X-Matix-Key: $KEY" "$URL/api/v1/matix/uso"

# 4. Rate limit headers presentes
curl.exe -s -D - -o NUL -H "X-Matix-Key: $KEY" "$URL/api/v1/matix/uso" | findstr -i ratelimit
```

Si los 4 chequeos pasan, el cerebro está vivo en producción.

---

## 6. Compilar e instalar el APK release

### 6.1 Build apuntando a Railway

Desde la raíz del proyecto:

```powershell
cd app
flutter clean
flutter pub get

flutter build apk --release `
  --dart-define MATIX_API_URL=https://<tu-dominio>.up.railway.app `
  --dart-define MATIX_API_KEY=<la NUEVA MATIX_API_KEY> `
  --dart-define MATIX_ENV=prod
```

El APK queda en `app/build/app/outputs/flutter-apk/app-release.apk`.

### 6.2 Instalar

```powershell
$env:PATH += ";$env:LOCALAPPDATA\Android\Sdk\platform-tools"
adb devices                              # debe listar tu teléfono
adb install -r app/build/app/outputs/flutter-apk/app-release.apk
```

No hace falta `adb reverse` — el APK ya apunta a HTTPS público.

### 6.3 Validación final

Con el teléfono ya con el APK release:

1. **Desconectá el USB.**
2. **Apagá el WiFi del teléfono** y dejalo solo con datos móviles
   (o cambiá a un WiFi distinto del de tu casa).
3. Abrí Matix. La pestaña Inicio debe cargar.
4. Chat: mandale un mensaje a Matix.
5. Voz: tocá el botón mic; hablale algo corto.
6. Manos libres: entrá al modo, hablá, escuchá la respuesta.
7. Tools: pedile a Matix que cree una tarea. Andá a Tareas → debe
   aparecer.
8. Banner medidor arriba del chat: el costo USD sigue subiendo.

Si todo funciona desde datos móviles, **despliegue cerrado**.

---

## 7. Para el día a día

### 7.1 Desarrollar contra el cerebro local

Seguís haciendo lo mismo: `flutter run` con `MATIX_API_URL=http://localhost:8000`,
`adb reverse`. Nada cambió.

### 7.2 Actualizar el cerebro en la nube

`git push` a main → Railway re-buildea automáticamente. Si el deploy
falla, el anterior sigue sirviendo (Railway no corta hasta que el
nuevo pase healthcheck).

### 7.3 Ver consumo

- En la franja arriba del chat (lo agregaste en Capa 2 Paso 5).
- Pidiéndole a Matix "¿cuánto he gastado?" → usa la tool
  `consultar_uso`.
- En OpenAI Dashboard → **Usage** (datos definitivos del facturado).

### 7.4 Si Railway te avisa que se quedó sin crédito

El servicio pausa, no se pierde nada. Recargás $5 USD o pasás a
plan Hobby ($5/mes con crédito incluido). La BD vive en Supabase
(plan free hasta 500 MB), no en Railway, así que tus datos están a
salvo.
