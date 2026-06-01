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
