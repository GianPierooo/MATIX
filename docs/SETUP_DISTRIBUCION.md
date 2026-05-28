# Distribución automática del APK con Firebase App Distribution

Guía paso a paso de la **Fase B**: configurar Firebase, conectarlo a
GitHub Actions y validar que un push a `main` resulte en una
notificación de nueva versión en el teléfono.

Tiempo estimado: 30–40 min, casi todo configuración en dashboards.

> **Antes de arrancar** — la Fase A ya dejó listo:
>
> - `firebase_core` en `pubspec.yaml`.
> - Plugin `com.google.gms.google-services` en Gradle (se aplica
>   solo si `google-services.json` está presente).
> - `Firebase.initializeApp()` en `main.dart` (tolerante a la
>   ausencia del archivo).
> - `.gitignore` excluye `google-services.json`.
> - `.github/workflows/release.yml` con el workflow completo.

Resumen del flujo después de configurado:

```
  git push main
       │
       ▼
  GitHub Actions
   ├─ flutter pub get
   ├─ decodifica google-services.json (secret base64)
   ├─ flutter build apk --release  (con MATIX_API_URL/_KEY)
   └─ sube APK a Firebase App Distribution
       │
       ▼
  App Tester (en el teléfono)
   └─ notificación: "Hay una versión nueva"
       │
       ▼
  Tap → descarga → instala. Listo.
```

---

## 1. Proyecto Firebase

### 1.1 Crear el proyecto

1. Andá a https://console.firebase.google.com/.
2. Botón **"+ Add project"** (o "Crear proyecto").
3. **Nombre**: `matix` (o `matix-prod`, lo que prefieras).
4. **Google Analytics**: **desactivá**. No la necesitamos y simplifica el
   onboarding.
5. **Create project** → esperar unos segundos.

### 1.2 Agregar la app Android

Dentro del proyecto:

1. En el centro de la pantalla, ícono Android (o **"+ Add app"** → Android).
2. **Android package name**: exactamente
   ```
   dev.matix.matix
   ```
   (es el `applicationId` que ya tiene la app Flutter; importante que
   coincida o el APK no se asocia al proyecto Firebase).
3. **App nickname** (opcional): `Matix Android`.
4. **Debug signing certificate SHA-1**: dejar vacío. Solo se necesita
   para algunos servicios (Auth con Google, Dynamic Links) que no
   usamos.
5. **Register app**.

### 1.3 Descargar `google-services.json`

Firebase ahora te muestra el archivo `google-services.json`.

1. Descargalo.
2. Guardalo en
   ```
   app/android/app/google-services.json
   ```
   exactamente con ese nombre y en esa ruta. Es la única ubicación
   que el plugin de Gradle conoce.
3. **No lo commitees** — `.gitignore` ya lo excluye.

Probá que el build local sigue funcionando con el archivo en su sitio:

```powershell
cd app
flutter build apk --debug
```

Debería terminar sin errores. Si te tira un error tipo "missing
project number" o similar, revisá que el JSON esté entero y bien
nombrado.

### 1.4 Activar App Distribution

1. Menú lateral izquierdo → **App Distribution** (bajo "Release & Monitor").
2. **Get started**. Acepta los términos.
3. **Testers & Groups** (pestaña arriba) → **Add group** → nombre
   **`testers`** (exacto, en minúscula — el workflow ya está
   configurado con ese nombre de grupo).
4. **Add testers**: agregás los emails de las cuentas Google de los
   testers. Para vos solo: tu propio email.

---

## 2. Service account para CI

GitHub Actions necesita una credencial de Google con permiso para
subir builds a App Distribution.

### 2.1 Generar la service account

1. En la consola Firebase → ícono engranaje (⚙) arriba a la izquierda
   → **Project settings**.
2. Pestaña **Service accounts**.
3. Botón **Manage service account permissions** → te lleva a la
   consola de Google Cloud (mismo proyecto, otra UI).
4. En esa página, **+ Create service account**.
   - **Name**: `github-actions-distribution`.
   - **Description**: `Sube APKs al App Distribution desde CI`.
   - **Create and continue**.
5. **Grant access**: rol **"Firebase App Distribution Admin"**.
   - **Continue** → **Done**.
6. En la lista de service accounts, encontrá la que acabás de crear
   → tres puntos → **Manage keys** → **Add key** → **Create new key**
   → **JSON** → **Create**.
7. Se descarga un archivo `.json` con la credencial. **Es el secret
   más sensible de toda la cadena**: guardalo y no lo commitees.

### 2.2 Conseguir el `FIREBASE_APP_ID`

1. Volvé a la consola Firebase → ⚙ Project settings → pestaña **General**.
2. En **Your apps** → tu app Android.
3. Copiá el **App ID**. Formato: `1:1234567890123:android:abc...`

---

## 3. Configurar los secrets en GitHub

En el repo de GitHub:

1. **Settings** del repo → **Secrets and variables** → **Actions**.
2. Botón **"New repository secret"** para cada uno:

| Secret | Valor |
|--------|-------|
| `MATIX_API_URL` | `https://matix-production.up.railway.app` (la URL pública que generaste en Railway) |
| `MATIX_API_KEY` | El mismo valor que tenés en `cerebro/.env` local |
| `GOOGLE_SERVICES_JSON_B64` | El contenido de `google-services.json` codificado en base64 (ver 3.1) |
| `FIREBASE_APP_ID` | El App ID que copiaste en 2.2 (`1:…:android:…`) |
| `FIREBASE_SERVICE_ACCOUNT_B64` | El JSON de credencial descargado en 2.1, codificado en base64 (ver 3.2) |

### 3.1 Cómo codificar `google-services.json` en base64

En PowerShell:

```powershell
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes("app\android\app\google-services.json"))
$b64 | Set-Clipboard
Write-Host "Base64 ($($b64.Length) chars) en el portapapeles."
```

Pegá el contenido del portapapeles en el secret `GOOGLE_SERVICES_JSON_B64`.

> Alternativa (si no anda lo de arriba): abrí el archivo y usá
> https://www.base64encode.org/ con la opción "Encode each line
> separately" **desactivada**.

### 3.2 Cómo codificar el JSON de la service account en base64

PowerShell tiene un bug sutil que mete BOM al pasar strings por
stdin a `gh secret set`. Para evitarlo, el secret va en base64 (bytes
puros, sin encoding shenanigans). Comando:

```powershell
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\ruta\a\service-account.json"))
$b64 | Set-Clipboard
Write-Host "Base64 ($($b64.Length) chars) en el portapapeles."
```

Pegá el contenido del portapapeles en el secret `FIREBASE_SERVICE_ACCOUNT_B64`.

El workflow lo decodifica en CI con `base64 -d` y verifica que el
JSON resultante es parseable antes de usarlo.

---

## 4. Tester en el teléfono

### 4.1 Aceptar la invitación

1. En el dashboard de Firebase App Distribution, cuando agregaste tu
   email como tester (paso 1.4), te llegó (o te llegará al primer
   build) un mail de Firebase: **"You've been invited to test Matix"**.
2. Abrilo en el teléfono.
3. Toca el botón **"Get started"** o **"Accept invitation"**.
4. Firebase te guía a instalar la app **"App Tester"** desde el Play
   Store.

### 4.2 Instalar la app "App Tester"

- Buscá en Play Store: **"Firebase App Tester"**.
- Instalala y abrila con la misma cuenta Google que registraste como
  tester.
- Vas a ver el proyecto Matix listado. Cuando haya un build nuevo,
  aparece ahí (y opcionalmente notifica).

### 4.3 Permitir instalación de fuentes desconocidas

La primera vez que querés instalar un APK desde App Tester, Android
te va a pedir permiso. **Settings** → buscás "Install unknown apps"
o "Instalar apps de fuente desconocida" → permitís a "App Tester".

---

## 5. Validación final

### 5.1 Disparar el primer build

Hacé un cambio chiquito en la app — por ejemplo, cambiá el saludo
de Inicio o un texto del chat. Algo visible.

```powershell
git add app/
git commit -m "test: distribución automática"
git push
```

### 5.2 Ver el workflow correr

1. En GitHub → pestaña **Actions** del repo.
2. Vas a ver un run nuevo "Release APK · Firebase App Distribution".
3. Tocalo. Ves los pasos en orden:
   - Checkout, Setup Java, Setup Flutter (~2 min)
   - Flutter pub get (~30s)
   - Decode google-services.json (instant)
   - Build APK release (~3-5 min la primera vez, después menos por cache)
   - Subir a Firebase App Distribution (~30s)
   - Backup como artifact (~10s)
4. Si todo verde → el APK ya está en Firebase.

### 5.3 Recibir en el teléfono

A los pocos minutos (a veces ~1 min, a veces 5–10):

- App Tester muestra el build nuevo (probablemente con notificación push si Android dio el permiso).
- Tocás → **Download** → instalá (Android va a pedir confirmación, normal).
- Abrís Matix → ves el cambio.

🎉 Si eso funciona, **distribución cerrada**. Cada `git push` a `main` que toque `app/` resulta en una build nueva en el teléfono sin tocar el cable.

---

## 6. Troubleshooting

### El workflow falla en "Build APK release"

Mirá los logs del paso. Causas comunes:

- `google-services.json` malformado (algún error decodificando el
  base64). Volvé a generar el secret con el comando de 3.1.
- `MATIX_API_KEY` no configurado → la app compila pero al arrancar
  no puede hablar con el cerebro. Verificá el secret.

### El workflow falla en "Subir a Firebase App Distribution"

- **"App ID not found"**: el `FIREBASE_APP_ID` secret está mal. Vuelve
  a copiarlo de Project Settings → General → Your apps.
- **"Permission denied" / "Invalid service account"**: el JSON de
  la service account está mal pegado, o le falta el rol "Firebase
  App Distribution Admin".
- **"Group testers not found"**: no creaste el grupo, o lo nombraste
  distinto. Andá a App Distribution → Testers & Groups y verificá
  que exista un grupo llamado **`testers`** (lowercase).

### El build sube pero el teléfono no notifica

- Confirmá que el email que registraste como tester es la cuenta
  Google con la que abriste App Tester.
- En App Tester, hacé pull-to-refresh — a veces tarda en llegar la
  notif push.
- Si nada aparece, mirá el dashboard de Firebase App Distribution →
  Releases. Si el build está ahí, es solo timing.

### Quiero subir un build manual sin hacer commit

GitHub → Actions → workflow "Release APK …" → **"Run workflow"** →
branch `main` → **Run workflow**. Disparás el mismo pipeline sin
cambios de código (útil para rebuildar después de rotar `MATIX_API_KEY`).

---

## 7. Día a día

- **Cambios al cerebro**: `git push` → Railway redeployea solo.
- **Cambios a la app**: `git push` → GitHub Actions builda → App
  Tester notifica → instalás de un toque.
- **Rotar una clave**: actualizá el secret en GitHub Actions →
  disparás "Run workflow" → llega un APK nuevo con la key nueva
  embebida.
