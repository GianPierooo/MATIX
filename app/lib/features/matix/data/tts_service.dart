import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../api/matix_client.dart';
import '../../../config.dart';

/// Reproductor de audio detrás de una interfaz chica, para poder testear el
/// TTS sin tocar el reproductor real ni el sistema de archivos.
///
/// Recibe los BYTES del mp3 (no una ruta): así `TtsService` no toca disco y
/// es testeable con un fake. El `reproduciendo` avisa cuándo SUENA de verdad
/// (no cuando se descarga), que es lo que sincroniza el visual con el audio.
abstract class ReproductorAudio {
  /// Reproduce los bytes del mp3. Devuelve cuando arrancó el play (no cuando
  /// terminó). El fin llega por [alCompletar].
  Future<void> reproducir(List<int> mp3);

  /// Corta la reproducción en curso.
  Future<void> detener();

  /// `true` cuando empieza a sonar, `false` cuando para o termina. La UI lo
  /// usa para pulsar la onda SOLO mientras realmente hay audio.
  Stream<bool> get reproduciendo;

  /// Emite cuando el audio termina naturalmente.
  Stream<void> get alCompletar;

  Future<void> liberar();
}

/// Implementación real con `audioplayers`: escribe el mp3 a un temporal y lo
/// reproduce; mapea el estado del reproductor a `reproduciendo`.
class ReproductorAudioPlayers implements ReproductorAudio {
  final AudioPlayer _player = AudioPlayer();
  File? _ultimoArchivo;

  @override
  Stream<bool> get reproduciendo =>
      _player.onPlayerStateChanged.map((s) => s == PlayerState.playing);

  @override
  Stream<void> get alCompletar => _player.onPlayerComplete;

  @override
  Future<void> reproducir(List<int> mp3) async {
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ruta = '${dir.path}/matix_tts_$ts.mp3';
    await File(ruta).writeAsBytes(mp3, flush: true);
    await _borrarSiExiste(_ultimoArchivo);
    _ultimoArchivo = File(ruta);
    await _player.play(DeviceFileSource(ruta));
  }

  @override
  Future<void> detener() => _player.stop();

  @override
  Future<void> liberar() async {
    await _player.dispose();
    await _borrarSiExiste(_ultimoArchivo);
  }

  Future<void> _borrarSiExiste(File? f) async {
    if (f == null) return;
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

/// Contrato del TTS para el modo manos libres (permite inyectar un fake).
abstract class TtsBase {
  /// Lee `texto` con la voz de Matix. `onInicio` se llama cuando el audio
  /// EMPIEZA A SONAR de verdad (no cuando se descarga), para que el visual
  /// arranque junto con el audio. Devuelve cuando el audio termina (o lo
  /// cortó `detener`).
  Future<void> hablar(String texto, {void Function()? onInicio});

  /// Corta la reproducción y resuelve el `hablar` en curso (audio + espera
  /// paran juntos).
  Future<void> detener();

  Future<void> dispose();
}

/// Text-to-Speech del modo manos libres (voz `onyx` de OpenAI vía el cerebro).
///
/// Flujo: app → POST /api/v1/matix/voz → OpenAI (el cerebro autentica). La
/// app recibe el mp3 y lo reproduce. La descarga ocurre ANTES de sonar, así
/// que `onInicio` solo dispara cuando el reproductor entra en `playing`: eso
/// es lo que mantiene el visual sincronizado con el audio.
class TtsService implements TtsBase {
  TtsService({http.Client? inner, ReproductorAudio? reproductor})
      : _inner = inner ?? http.Client(),
        _rep = reproductor ?? ReproductorAudioPlayers() {
    _completionSub = _rep.alCompletar.listen((_) => _completar());
    _estadoSub = _rep.reproduciendo.listen((rep) {
      if (rep && !_inicioNotificado) {
        _inicioNotificado = true;
        _onInicio?.call();
      }
    });
  }

  final http.Client _inner;
  final ReproductorAudio _rep;
  late final StreamSubscription<void> _completionSub;
  late final StreamSubscription<bool> _estadoSub;

  Completer<void>? _completer;
  void Function()? _onInicio;
  bool _inicioNotificado = false;

  @override
  Future<void> hablar(String texto, {void Function()? onInicio}) async {
    final t = texto.trim();
    if (t.isEmpty) return;

    // Si veníamos reproduciendo, cortamos y limpiamos.
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete();
      _completer = null;
      await _rep.detener();
    }

    _onInicio = onInicio;
    _inicioNotificado = false;

    // 1) Pedir el mp3 al cerebro (esto NO suena todavía).
    final mp3 = await _descargar(t);

    // 2) Reproducir; `onInicio` dispara cuando entra en `playing`, y el
    // completer se resuelve al terminar (o por `detener`).
    _completer = Completer<void>();
    await _rep.reproducir(mp3);
    await _completer!.future;
  }

  @override
  Future<void> detener() async {
    await _rep.detener();
    _completar();
  }

  @override
  Future<void> dispose() async {
    await detener();
    await _completionSub.cancel();
    await _estadoSub.cancel();
    await _rep.liberar();
    _inner.close();
  }

  void _completar() {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete();
    }
    _completer = null;
  }

  // ── internos ──────────────────────────────────────────────────────

  Future<List<int>> _descargar(String texto) async {
    final uri = Uri.parse('${MatixConfig.apiUrl}/api/v1/matix/voz');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (MatixConfig.hasApiKey) 'X-Matix-Key': MatixConfig.apiKey,
    };
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
}

/// Encoder JSON-string mínimo para escapar `"`, `\`, y los pocos caracteres
/// de control que pueden aparecer en texto generado por LLM.
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
