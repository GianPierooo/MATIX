import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
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

/// Voz NATIVA del dispositivo (piso siempre disponible). Cuando la TTS en la
/// nube (OpenAI/ElevenLabs vía cerebro) no responde, hablamos con esto en vez
/// de quedarnos en texto. Interfaz chica para poder inyectar un fake en tests.
abstract class VozDispositivo {
  /// Lee `texto` con la voz del teléfono. Devuelve `true` si habló.
  Future<bool> hablar(String texto);
  Future<void> detener();
}

/// Implementación real con `flutter_tts` (motor TTS del sistema, es-ES).
///
/// La config (idioma) es LAZY dentro de `hablar`, no en el constructor: así
/// construir el servicio no dispara llamadas al canal nativo (que en tests no
/// existe) y no genera errores async sueltos.
class VozDispositivoFlutterTts implements VozDispositivo {
  // LAZY: `FlutterTts()` llama `setMethodCallHandler` en su constructor, que
  // requiere el binding de Flutter. Construirlo solo al usar el respaldo evita
  // tocar el canal nativo en el camino normal (cloud OK) y en tests.
  FlutterTts? _instancia;
  FlutterTts get _tts => _instancia ??= FlutterTts();
  bool _configurado = false;

  Future<void> _configurar() async {
    if (_configurado) return;
    await _tts.setLanguage('es-ES');
    await _tts.awaitSpeakCompletion(true);
    _configurado = true;
  }

  @override
  Future<bool> hablar(String texto) async {
    try {
      await _configurar();
      await _tts.stop();
      final r = await _tts.speak(texto);
      // En Android `speak` devuelve 1 al encolar OK; algunos motores no
      // devuelven nada → asumimos que habló si no lanzó.
      return r == null || r == 1;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> detener() async {
    if (_instancia == null) return; // no instanciar solo para parar
    try {
      await _instancia!.stop();
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
  TtsService({
    http.Client? inner,
    ReproductorAudio? reproductor,
    VozDispositivo? vozDispositivo,
  })  : _inner = inner ?? http.Client(),
        _rep = reproductor ?? ReproductorAudioPlayers(),
        _voz = vozDispositivo ?? VozDispositivoFlutterTts() {
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
  final VozDispositivo _voz;
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

    try {
      // 1) Pedir el mp3 al cerebro (esto NO suena todavía).
      final mp3 = await _descargar(t);
      // 2) Reproducir; `onInicio` dispara cuando entra en `playing`, y el
      // completer se resuelve al terminar (o por `detener`).
      _completer = Completer<void>();
      await _rep.reproducir(mp3);
      await _completer!.future;
    } catch (_) {
      // TTS en la nube caído (sin crédito / 5xx) → voz NATIVA del dispositivo
      // (piso siempre disponible). Si el dispositivo tampoco habla, silencio
      // (el texto ya está en pantalla). Nunca lanza.
      onInicio?.call();
      await _voz.hablar(t);
    }
  }

  /// Narra en SEGUNDO PLANO: descarga + reproduce sin bloquear al caller y sin
  /// lanzar NUNCA. Si el TTS falla (502/timeout, ya con reintentos), se queda
  /// en silencio — el texto ya está en pantalla. Para la cámara en vivo: la voz
  /// jamás debe bloquear el loop ni tumbar la sesión. Corta lo previo: la última
  /// narración manda.
  /// [onFallo] se llama si la voz no salió (tras reintentos). El caller puede
  /// mostrar un aviso honesto ("voz no disponible, sigo en texto") sin que esto
  /// rompa nada.
  /// [onDispositivo] se llama si la voz salió por el respaldo NATIVO del
  /// teléfono (cloud caído). El caller puede mostrar "usando la voz del
  /// teléfono". [onFallo] solo si NI el dispositivo pudo hablar.
  void narrar(
    String texto, {
    void Function()? onFallo,
    void Function()? onDispositivo,
  }) {
    final t = texto.trim();
    if (t.isEmpty) return;
    unawaited(_narrarSeguro(t, onFallo, onDispositivo));
  }

  Future<void> _narrarSeguro(
    String t,
    void Function()? onFallo,
    void Function()? onDispositivo,
  ) async {
    try {
      if (_completer != null && !_completer!.isCompleted) {
        _completer!.complete();
        _completer = null;
        await _rep.detener();
      }
      _onInicio = null;
      _inicioNotificado = false;
      final mp3 = await _descargar(t);
      _completer = Completer<void>();
      await _rep.reproducir(mp3);
      // NO esperamos el fin del audio: el caller (cámara) sigue su ritmo.
    } catch (_) {
      // Cloud TTS caído → voz NATIVA del teléfono (piso siempre disponible).
      // Solo si el dispositivo TAMPOCO habla nos quedamos en texto.
      final hablo = await _voz.hablar(t);
      if (hablo) {
        onDispositivo?.call();
      } else {
        onFallo?.call();
      }
    }
  }

  @override
  Future<void> detener() async {
    await _rep.detener();
    await _voz.detener();
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

  /// Descarga el mp3 con REINTENTOS y backoff ante fallos transitorios
  /// (502/503/504/timeout/red). Antes un solo 502 pasajero de OpenAI tumbaba la
  /// voz; ahora reintenta hasta 3 veces (250ms, 500ms) y solo entonces relanza,
  /// para que el caller degrade (texto sin voz). Errores legítimos (400/401) no
  /// se reintentan: se relanzan al toque.
  static const _maxIntentos = 3;

  Future<List<int>> _descargar(String texto) async {
    for (var intento = 1;; intento++) {
      try {
        return await _descargarUnaVez(texto);
      } on MatixApiException catch (e) {
        if (!_esTransitorio(e.statusCode) || intento >= _maxIntentos) rethrow;
      } on TimeoutException {
        if (intento >= _maxIntentos) rethrow;
      } catch (_) {
        // Errores de red (SocketException, handshake…): transitorios.
        if (intento >= _maxIntentos) rethrow;
      }
      await Future<void>.delayed(
        Duration(milliseconds: 250 * (1 << (intento - 1))),
      );
    }
  }

  bool _esTransitorio(int code) =>
      code == 408 || code == 429 || code == 502 || code == 503 || code == 504;

  Future<List<int>> _descargarUnaVez(String texto) async {
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
