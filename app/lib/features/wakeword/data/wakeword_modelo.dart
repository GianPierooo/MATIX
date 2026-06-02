/// Fuente ÚNICA de verdad del modelo de wake word: qué archivo .onnx se usa de
/// clasificador y qué frase se muestra en la UI.
///
/// Para pasar del placeholder en inglés a "oye matix" en español:
///  1. Entrena el modelo en Colab (ver `docs/entrenar_oye_matix.md`).
///  2. Pon `oye_matix.onnx` en `app/assets/models/wakeword/`.
///  3. Cambia las DOS constantes de aquí abajo:
///       archivo = 'oye_matix.onnx'
///       frase   = 'oye matix'
///  4. (Native) la notificación del service de fondo ya es genérica, no hace
///     falta tocar Kotlin: Dart le pasa el nombre del archivo por el canal.
///
/// La cadena compartida (melspectrograma + embedding) NO cambia: el modelo
/// entrenado tiene la misma interfaz [1,16,96] -> [1,1] que hey_jarvis.
class WakeWordModelo {
  const WakeWordModelo._();

  /// Archivo del clasificador dentro de `assets/models/wakeword/`. Lo usan el
  /// pipeline Dart (app abierta) y, vía el canal, el service nativo (segundo
  /// plano), así que cambiarlo aquí cambia AMBOS.
  static const String archivo = 'hey_jarvis_v0.1.onnx';

  /// Frase que se muestra en la UI (sin comillas).
  static const String frase = 'hey jarvis';
}
