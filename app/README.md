# matix

Matix - asistente personal y centro de mando

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Compilar release con config PROD e instalar al device por USB (dev)

Para iterar en un teléfono físico con la MISMA config que publica el CI (URL de
Railway, entorno `prod`, API key) sin pasar por el OTA:

```powershell
# 1) Una sola vez: pon la API key de prod (la misma de cerebro/.env) en un
#    archivo local NO versionado (.gitignore lo cubre):
copy tools\.env.prod.local.example tools\.env.prod.local
#    edita tools\.env.prod.local y pega:  MATIX_API_KEY=<la key>
#    (alternativa sin archivo:  $env:MATIX_API_KEY = '<la key>')

# 2) Compilar release arm64 con config prod + instalar al device conectado:
powershell -File tools\instalar-prod.ps1
```

El script (`tools/instalar-prod.ps1`) reproduce los `--dart-define` del CI
(`MATIX_API_URL`, `MATIX_API_KEY`, `MATIX_ENV=prod`, `MATIX_BUILD_NUMBER`),
compila `--release --target-platform android-arm64`, desinstala la versión
previa (el APK local va firmado con la debug keystore, distinta de la de release
del CI) e instala por `adb`. La API key se lee de `$env:MATIX_API_KEY` o de
`tools/.env.prod.local`; si falta, el script falla diciendo exactamente qué
poner. La key NUNCA se escribe en el repo ni se imprime.

Esto es SOLO para desarrollo local; no toca el workflow del CI ni el build de
prod publicado por OTA.

## Build — notas de dependencias nativas

### Wake word on-device ("oye Matix")

La detección de la palabra de activación corre on-device con la cadena ONNX de
[openWakeWord](https://github.com/dscripka/openWakeWord) directamente en Dart
(sin servicio nativo Kotlin). Dependencias y assets:

- **`flutter_onnxruntime`** — trae ONNX Runtime nativo (Android arm64/arm32,
  compatible con el page size de 16 KB). Se descarga al hacer `flutter pub get`
  y se enlaza vía Gradle; no requiere pasos manuales. La primera build de
  Android baja los binarios nativos, así que tarda algo más.
- **`record`** — además de grabar voz (m4a), su `startStream` entrega PCM16
  mono 16 kHz crudo, que es lo que come la tubería del wake word.
- **Modelos ONNX** en `assets/models/wakeword/` (declarados en `pubspec.yaml`):
  - `melspectrogram.onnx` + `embedding_model.onnx` — cadena compartida.
  - `hey_jarvis_v0.1.onnx` — clasificador de la **palabra de prueba**
    ("hey jarvis"). Para pasar a "oye matix" solo se reemplaza este archivo.

  Todos vienen de la release `v0.5.1` del repo de openWakeWord. Si hubiera que
  rebajarlos:

  ```bash
  base=https://github.com/dscripka/openWakeWord/releases/download/v0.5.1
  for f in melspectrogram.onnx embedding_model.onnx hey_jarvis_v0.1.onnx; do
    curl -sL -o assets/models/wakeword/$f $base/$f
  done
  ```

- **Permiso**: usa `RECORD_AUDIO` (ya declarado para la voz). Umbral de
  detección por defecto: `0.30` (ajustable con el slider de Ajustes; bajo porque
  "hey jarvis" es un modelo en inglés y los scores en español son bajos).

### Escucha en segundo plano (foreground service nativo)

Un toggle SEPARADO en Ajustes ("Escuchar en segundo plano") enciende un
**foreground service de micrófono** (`WakeWordService.kt`) que corre la cadena
ONNX en **Kotlin** (vía la API Java `ai.onnxruntime`, sin engine de Flutter) y
escucha con la app cerrada / pantalla apagada / bloqueada. Al detectar, abre el
modo de voz con un **full-screen intent** (patrón de llamada entrante:
`MainActivity` con `showWhenLocked` + `turnScreenOn`), que es la vía soportada
para lanzar UI desde background en Android 10+. El service es `START_STICKY`
(el SO intenta recrearlo si lo mata).

- Dependencia nativa: `com.microsoft.onnxruntime:onnxruntime-android:1.22.0`
  (declarada explícita en `build.gradle.kts`; flutter_onnxruntime ya la trae
  transitiva, Gradle deduplica el `.aar`).
- Permisos: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`,
  `USE_FULL_SCREEN_INTENT`, `WAKE_LOCK`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.
- El foreground (app abierta) y el segundo plano se relevan por ciclo de vida:
  en `paused` se arranca el service y se para el escuchador Dart; en `resumed`,
  al revés. Un solo dueño del micro a la vez.

**MagicOS / Honor — pasos manuales (NO se pueden forzar por código).** Este OEM
mata agresivo los servicios en background (mismo motivo por el que las notifs se
movieron a FCM). Al activar el toggle se pide la excepción de batería; además el
usuario debe, a mano:

1. **Ajustes del sistema > Batería > Lanzamiento de aplicaciones > Matix**:
   ponerlo en **Gestionar manualmente** y activar **Autoarranque**, **Arranque
   secundario** y **Ejecutar en segundo plano**.
2. **Recientes**: deslizar hacia abajo sobre Matix para **bloquear** la tarjeta
   (candado), así no la barre el limpiador.
3. Aceptar el diálogo de **ignorar optimización de batería** que aparece al
   encender el toggle.

Aun así MagicOS puede matar el service; por eso es `START_STICKY`. Si la escucha
de fondo deja de responder, reabrir la app lo reinicia.
