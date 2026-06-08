import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show debugPrint;
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

  /// Inicializa el motor EAGER (idioma, volumen, velocidad, modo FLUSH). Idem-
  /// potente. Devuelve true si el motor quedó listo para hablar de inmediato.
  /// Hacerlo al abrir la cámara evita que el primer frame pague la latencia de
  /// configuración (que en algunos OEM se traga la primera frase entera).
  Future<bool> preparar();

  /// El último idioma TTS que se logró setear (`es-419`, `es-PE`, …). Útil para
  /// diagnosticar en qué locale habla el motor del Honor del user. Null si nada.
  String? get idiomaActivo;
}

/// Implementación real con `flutter_tts` (motor TTS del sistema).
///
/// Optimizada para narración EN VIVO (cámara): idioma con fallback Latam-first,
/// volumen y rate altos, modo FLUSH (una `speak` nueva CORTA la anterior), y
/// `awaitSpeakCompletion(false)` para que `speak()` retorne ya y el caller
/// pueda interrumpir al siguiente frame sin esperar a que termine la frase.
///
/// La instancia de `FlutterTts` es LAZY (requiere el binding de Flutter, no
/// existe en tests). `preparar()` es idempotente y se debe llamar al abrir la
/// pantalla — antes el config corría dentro de `hablar()` y la primera frase
/// pagaba la latencia.
class VozDispositivoFlutterTts implements VozDispositivo {
  FlutterTts? _instancia;
  FlutterTts get _tts => _instancia ??= FlutterTts();
  bool _configurado = false;
  String? _idiomaActivo;

  /// Orden de intento: español Latam primero (el motor del Honor del user suele
  /// venir con `es-419`/`es-PE` y NO con `es-ES`). Antes solo intentábamos
  /// `es-ES` y, si el motor no lo tenía, `setLanguage` lanzaba y la voz quedaba
  /// muda sin un mensaje claro.
  static const List<String> _idiomasEnOrden = [
    'es-419', // Latin American Spanish
    'es-PE',
    'es-MX',
    'es-US',
    'es-CO',
    'es-AR',
    'es-ES',
  ];

  @override
  String? get idiomaActivo => _idiomaActivo;

  @override
  Future<bool> preparar() async {
    if (_configurado) return true;
    try {
      // Volumen + velocidad para narración en vivo: clara y un toque por encima
      // del default lento de Android (~0.5).
      await _tts.setVolume(1.0);
      await _tts.setSpeechRate(0.55);
      await _tts.setPitch(1.0);
      // Modo FLUSH: una nueva `speak()` corta la anterior. Si el motor no lo
      // soporta (algún OEM raro), no es fatal: caemos a `stop()` antes de cada
      // speak. Por eso va en try/catch.
      try {
        await _tts.setQueueMode(0);
      } catch (_) {}
      // FALSO: `speak()` retorna en cuanto ENCOLA, no cuando termina. Para la
      // cámara queremos esto: el caller no espera el fin de la frase.
      await _tts.awaitSpeakCompletion(false);
      // Idioma: primero el preferido disponible, sin lanzar si no está.
      _idiomaActivo = await _setearPrimerIdiomaDisponible();
      if (_idiomaActivo == null) {
        debugPrint('[tts][dispositivo] ningún idioma es-* disponible en el motor');
        return false;
      }
      debugPrint('[tts][dispositivo] preparado (lang=$_idiomaActivo)');
      _configurado = true;
      return true;
    } catch (e) {
      debugPrint('[tts][dispositivo] preparar falló: $e');
      return false;
    }
  }

  /// Intenta cada idioma del orden hasta que uno responde "disponible". Devuelve
  /// el que quedó seteado o null si ninguno aplicó.
  Future<String?> _setearPrimerIdiomaDisponible() async {
    for (final lang in _idiomasEnOrden) {
      try {
        final disp = await _tts.isLanguageAvailable(lang);
        if (disp != true) continue;
        final r = await _tts.setLanguage(lang);
        // Android: 1 = OK. Algunos motores devuelven null en éxito.
        if (r == 1 || r == null) return lang;
      } catch (_) {
        // Sigue con el próximo.
      }
    }
    // Último recurso: intentar `es-ES` a ciegas (algunos motores no implementan
    // isLanguageAvailable y siempre lo reportan como false).
    try {
      final r = await _tts.setLanguage('es-ES');
      if (r == 1 || r == null) return 'es-ES';
    } catch (_) {}
    return null;
  }

  @override
  Future<bool> hablar(String texto) async {
    try {
      if (!_configurado) {
        final ok = await preparar();
        if (!ok) return false;
      }
      // En modo FLUSH `stop()` no haría falta, pero algunos motores no respetan
      // el queueMode al pie de la letra; con esto garantizamos interrupción.
      await _tts.stop();
      final r = await _tts.speak(texto);
      return r == null || r == 1;
    } catch (e) {
      debugPrint('[tts][dispositivo] speak falló: $e');
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

/// Proveedor TTS que se intentó en un turno de narración. Para diagnóstico:
/// "qué eslabón falló". Lo expone `TtsService.ultimoEvento`.
enum ProveedorTts { dispositivo, cloud, ninguno }

class TtsEvento {
  const TtsEvento({
    required this.cuando,
    required this.proveedor,
    required this.exito,
    this.motivo,
  });

  final DateTime cuando;
  final ProveedorTts proveedor;
  final bool exito;
  final String? motivo;

  /// Texto compacto para chips/badges: "✓ dispositivo" / "✗ cloud (timeout)".
  String get etiqueta {
    final tick = exito ? '✓' : '✗';
    final p = proveedor.name;
    return motivo == null ? '$tick $p' : '$tick $p ($motivo)';
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
  // Época de narración: cada `narrar`/`hablar`/`detener` la incrementa. Una
  // descarga en vuelo que termina con época vieja YA fue superada por una
  // narración más nueva → NO se reproduce (evita encolar audio atrasado en la
  // cámara en vivo: la última narración manda, nada de minutos de audio viejo).
  int _epoca = 0;
  // Instrumentación del último intento (para la chip de diagnóstico en la cámara
  // y para debug). Se actualiza en cada `narrarRapido`/`narrar` que tome decisión.
  TtsEvento? _ultimoEvento;
  TtsEvento? get ultimoEvento => _ultimoEvento;

  void _emitir(ProveedorTts proveedor, bool exito, [String? motivo]) {
    final e = TtsEvento(
      cuando: DateTime.now(),
      proveedor: proveedor,
      exito: exito,
      motivo: motivo,
    );
    _ultimoEvento = e;
    debugPrint('[tts] ${e.etiqueta}');
  }

  /// Inicializa el motor del DISPOSITIVO eagerly. Llamar al abrir una pantalla
  /// que vaya a usar `narrarRapido` (cámara en vivo): así la PRIMERA frase ya
  /// sale a la velocidad de un toque, sin pagar el setup.
  Future<bool> prepararDispositivo() => _voz.preparar();

  /// Idioma TTS activo en el dispositivo (`es-419`, `es-PE`, …). Útil para el
  /// chip de diagnóstico de la cámara.
  String? get idiomaDispositivo => _voz.idiomaActivo;

  @override
  Future<void> hablar(String texto, {void Function()? onInicio}) async {
    final t = texto.trim();
    if (t.isEmpty) return;
    _epoca++; // esta narración supera a cualquier descarga en vuelo

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

  /// Narración con PRIORIDAD AL DISPOSITIVO. Para la cámara en vivo: el TTS
  /// del dispositivo es ~instantáneo y siempre disponible; el cloud suma
  /// 0.5–2s de red y a veces falla silenciosamente. Si el dispositivo no
  /// habla, el cloud entra como RESPALDO. Si ninguno habla, `onFallo`.
  ///
  /// Diferencias con `narrar()`:
  ///  - Device-first (más rápido, simultáneo con el texto).
  ///  - Sin "epoca-guard" que estrangulaba el respaldo cuando llegaba un
  ///    frame nuevo durante el fallo del cloud (causa real del "no se oye nada"
  ///    en el modo anterior).
  ///  - Cada decisión emite un `TtsEvento` con proveedor/éxito/motivo
  ///    accesible vía `ultimoEvento` (para el chip de diagnóstico en pantalla).
  ///
  /// Reusa la misma cadena de descarga del cloud (`_descargar` con reintentos)
  /// y el mismo reproductor — no duplica nada.
  void narrarRapido(
    String texto, {
    void Function()? onFallo,
    void Function()? onDispositivo,
    void Function()? onCloud,
  }) {
    final t = texto.trim();
    if (t.isEmpty) return;
    unawaited(_narrarRapidoSeguro(t, onFallo, onDispositivo, onCloud));
  }

  Future<void> _narrarRapidoSeguro(
    String t,
    void Function()? onFallo,
    void Function()? onDispositivo,
    void Function()? onCloud,
  ) async {
    final miEpoca = ++_epoca;
    // 1) Cortar cualquier audio en curso (cloud O dispositivo), inmediato.
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete();
      _completer = null;
      await _rep.detener();
    }
    await _voz.detener();

    // 2) DEVICE primero (rápido, sin red, lo que la cámara necesita).
    final hablo = await _voz.hablar(t);
    if (miEpoca != _epoca) {
      _emitir(ProveedorTts.dispositivo, false, 'superado por narración más nueva');
      return;
    }
    if (hablo) {
      _emitir(ProveedorTts.dispositivo, true);
      onDispositivo?.call();
      return;
    }

    // 3) Device falló: respaldo CLOUD. NO aplicamos epoca-guard al respaldo
    // (era el bug previo: si llegaba otro frame durante el catch, ningún audio
    // jamás sonaba). Aquí confiamos en el `_voz.detener` + `_rep.detener` de la
    // próxima llamada para cortar este respaldo si llega otra narración.
    _emitir(ProveedorTts.dispositivo, false, 'speak devolvió false');
    try {
      final mp3 = await _descargar(t);
      if (miEpoca != _epoca) {
        _emitir(ProveedorTts.cloud, false, 'superado durante descarga');
        return;
      }
      _completer = Completer<void>();
      await _rep.reproducir(mp3);
      _emitir(ProveedorTts.cloud, true, 'respaldo');
      onCloud?.call();
    } catch (e) {
      _emitir(ProveedorTts.cloud, false, '${e.runtimeType}');
      if (miEpoca == _epoca) onFallo?.call();
    }
  }

  Future<void> _narrarSeguro(
    String t,
    void Function()? onFallo,
    void Function()? onDispositivo,
  ) async {
    final miEpoca = ++_epoca; // reservo mi turno: si llega otra, quedo obsoleto
    try {
      if (_completer != null && !_completer!.isCompleted) {
        _completer!.complete();
        _completer = null;
        await _rep.detener();
      }
      _onInicio = null;
      _inicioNotificado = false;
      final mp3 = await _descargar(t);
      // Mientras descargaba pudo llegar una narración MÁS nueva: si así fue, no
      // reproduzco esta (audio desfasado). La última gana; nada de cola vieja.
      if (miEpoca != _epoca) return;
      _completer = Completer<void>();
      await _rep.reproducir(mp3);
      // NO esperamos el fin del audio: el caller (cámara) sigue su ritmo.
    } catch (_) {
      // Si ya me superó una narración más nueva, no hablo lo viejo ni por el
      // respaldo del teléfono.
      if (miEpoca != _epoca) return;
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
    _epoca++; // invalida cualquier descarga en vuelo: tras parar, nada suena
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
