import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../api/matix_client.dart';
import '../../../config.dart';

/// Servicio de Text-to-Speech para el modo manos libres (Capa 2
/// Paso 4 → 5.1).
///
/// **Cambio de motor (5.1)**: pasamos de `flutter_tts` (motor del
/// teléfono) a la TTS de OpenAI vía el cerebro. Razones:
/// - El Huawei del usuario no expone voces masculinas usables en
///   `flutter_tts`.
/// - OpenAI `tts-1` con `onyx` da una voz masculina natural y
///   consistente, sin depender del motor del teléfono.
/// - La API key sigue solo en el cerebro — el flujo es:
///   app → /api/v1/matix/voz → OpenAI (cerebro autentica).
///
/// Implementación:
/// 1. POST con `{texto, voz}` al endpoint del cerebro.
/// 2. Recibe mp3 bytes; los escribe a un archivo temporal.
/// 3. Reproduce con `audioplayers`. Como `awaitSpeakCompletion`
///    en flutter_tts, `hablar` se completa cuando el reproductor
///    termina (o el usuario lo corta con `detener`).
///
/// La interfaz pública (`hablar`/`detener`/`dispose`) no cambió —
/// el orquestador de manos libres sigue funcionando igual.
class TtsService {
  TtsService({http.Client? inner}) : _inner = inner ?? http.Client() {
    // El reproductor escucha el evento `onPlayerComplete`; cuando
    // dispara, completamos el future actual. Como el bind se hace
    // una vez, sobrevive a múltiples llamadas a `hablar`.
    _completionSub = _player.onPlayerComplete.listen((_) {
      _completer?.complete();
      _completer = null;
    });
  }

  final AudioPlayer _player = AudioPlayer();
  final http.Client _inner;
  late final StreamSubscription<void> _completionSub;

  Completer<void>? _completer;
  File? _ultimoArchivo;

  /// Lee `texto` con la voz de Matix. Si había una reproducción en
  /// curso, la corta primero. Devuelve cuando el audio termina (o
  /// el usuario tocó `detener`).
  Future<void> hablar(String texto) async {
    final t = texto.trim();
    if (t.isEmpty) return;

    // Si veníamos reproduciendo, cortamos y limpiamos.
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete();
      _completer = null;
      await _player.stop();
    }

    // 1) Pedir el mp3 al cerebro
    final mp3 = await _descargar(t);

    // 2) Escribirlo a un temporal para que audioplayers lo lea
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ruta = '${dir.path}/matix_tts_$ts.mp3';
    final archivo = File(ruta);
    await archivo.writeAsBytes(mp3, flush: true);

    // Limpiar el anterior (best-effort).
    await _borrarSiExiste(_ultimoArchivo);
    _ultimoArchivo = archivo;

    // 3) Reproducir; el completer se resuelve cuando el evento de
    // fin del reproductor dispare (o `detener` lo complete).
    _completer = Completer<void>();
    await _player.play(DeviceFileSource(ruta));
    await _completer!.future;
  }

  /// Detiene cualquier reproducción en curso. Seguro de llamar
  /// aunque no haya nada hablando.
  Future<void> detener() async {
    await _player.stop();
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete();
    }
    _completer = null;
  }

  Future<void> dispose() async {
    await detener();
    await _completionSub.cancel();
    await _player.dispose();
    _inner.close();
    await _borrarSiExiste(_ultimoArchivo);
  }

  // ── internos ──────────────────────────────────────────────────────

  Future<List<int>> _descargar(String texto) async {
    final uri = Uri.parse('${MatixConfig.apiUrl}/api/v1/matix/voz');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (MatixConfig.hasApiKey) 'X-Matix-Key': MatixConfig.apiKey,
    };
    // Body manual: encodear con dart:convert sería igual pero
    // queremos evitar otra import — y http acepta string body.
    final body = '{"texto": ${_encodeJsonString(texto)}, "voz": "onyx"}';
    final resp = await _inner
        .post(uri, headers: headers, body: body)
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw MatixApiException(
        resp.statusCode,
        'TTS falló (${resp.statusCode})',
      );
    }
    return resp.bodyBytes;
  }

  Future<void> _borrarSiExiste(File? f) async {
    if (f == null) return;
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

/// Encoder JSON-string mínimo para escapar `"`, `\`, y los pocos
/// caracteres de control que pueden aparecer en texto generado por
/// LLM. Evitamos `dart:convert` solo para no añadir un import a
/// este archivo — la lógica es trivial.
String _encodeJsonString(String s) {
  final buf = StringBuffer('"');
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    switch (c) {
      case 0x22:
        buf.write(r'\"');
      case 0x5c:
        buf.write(r'\\');
      case 0x0a:
        buf.write(r'\n');
      case 0x0d:
        buf.write(r'\r');
      case 0x09:
        buf.write(r'\t');
      default:
        if (c < 0x20) {
          buf.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
        } else {
          buf.writeCharCode(c);
        }
    }
  }
  buf.write('"');
  return buf.toString();
}
