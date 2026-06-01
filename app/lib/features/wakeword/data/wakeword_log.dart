import 'package:flutter/foundation.dart';

/// Log del wake word con un prefijo fijo, SIEMPRE (también en release).
///
/// La cadena ONNX corre por primera vez en hardware real al activar la palabra,
/// y un fallo ahí puede ser un crash nativo (SIGSEGV) que ningún try/catch de
/// Dart atrapa. Por eso registramos cada paso con la etiqueta `WAKEWORD:` —
/// aunque la app muera, en logcat se ve exactamente en qué punto. No va detrás
/// de `kDebugMode`: el APK del device es release.
///
/// Capturar en el teléfono:  adb logcat -s flutter | grep WAKEWORD
///
/// Nunca registres datos personales acá — solo pasos, tamaños y errores.
void wlog(String mensaje) {
  // debugPrint escribe a stdout → logcat (tag `flutter`) también en release.
  debugPrint('WAKEWORD: $mensaje');
}
