// Los params directos de `listen` (localeId/listenFor/pauseFor) siguen
// funcionando en speech_to_text 7.x; su reemplazo (SpeechListenOptions) varía
// por versión, así que mantenemos los directos y silenciamos la deprecación.
// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

/// Dictado con el reconocimiento de voz NATIVO de Android (speech_to_text).
///
/// Es el RESPALDO del dictado cuando Whisper (OpenAI, vía el cerebro) no está
/// disponible (sin crédito / caído). El dictado no debe morir por falta de GPT:
/// si el cloud falla, el usuario vuelve a hablar y el teléfono lo transcribe.
///
/// A diferencia del flujo cloud (grabar archivo → subir → Whisper), el nativo
/// escucha EN VIVO: hace su propia sesión de micrófono y devuelve el texto.
class DictadoNativoService {
  final SpeechToText _stt = SpeechToText();
  bool _inicializado = false;

  Future<bool> _asegurarInit() async {
    if (_inicializado) return true;
    try {
      _inicializado = await _stt.initialize(
        onError: (_) {},
        onStatus: (_) {},
      );
    } catch (_) {
      _inicializado = false;
    }
    return _inicializado;
  }

  /// ¿Hay reconocedor nativo disponible en este dispositivo?
  Future<bool> disponible() => _asegurarInit();

  /// Escucha una frase y devuelve el texto reconocido (o '' si nada/!disponible).
  Future<String> escuchar({
    Duration limite = const Duration(seconds: 15),
  }) async {
    if (!await _asegurarInit()) return '';
    final completer = Completer<String>();
    var ultimo = '';
    try {
      await _stt.listen(
        localeId: 'es_ES',
        listenFor: limite,
        pauseFor: const Duration(seconds: 3),
        onResult: (r) {
          ultimo = r.recognizedWords;
          if (r.finalResult && !completer.isCompleted) {
            completer.complete(ultimo);
          }
        },
      );
    } catch (_) {
      return '';
    }
    // Red de seguridad: si nunca llega `finalResult` (timeout), resolvemos con
    // lo último que se escuchó.
    Future<void>.delayed(limite + const Duration(seconds: 1), () {
      if (!completer.isCompleted) completer.complete(ultimo);
    });
    final texto = await completer.future;
    try {
      await _stt.stop();
    } catch (_) {}
    return texto.trim();
  }

  Future<void> detener() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }
}
