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

- **Permiso**: usa `RECORD_AUDIO` (ya declarado para la voz). El escuchador
  solo corre con la app en primer plano (v1) y suelta el micro cuando arranca
  el modo manos libres. Umbral de detección por defecto: `0.5`.
