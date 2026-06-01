import 'dart:async';
import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'onnx_backend.dart';
import 'wakeword_crumbs.dart';
import 'wakeword_log.dart';
import 'wakeword_pipeline.dart';

/// Excepción cuando no hay permiso de micrófono para escuchar la palabra.
class PermisoWakeWordDenegado implements Exception {
  PermisoWakeWordDenegado(this.permanente);

  /// `true` si el usuario marcó "no preguntar más" → hay que mandarlo a los
  /// ajustes del sistema.
  final bool permanente;
}

/// Lo que el controller necesita del escuchador. Se deja como interfaz para
/// inyectar un fake en tests (el real abre el micro y carga ONNX nativo).
abstract class WakeWordEscucha {
  bool get activo;
  Future<void> iniciar({
    required double umbral,
    required void Function() onDeteccion,
    void Function(double score)? onScore,
  });
  Future<void> detener();
  Future<void> liberar();
}

/// Escuchador de wake word on-device.
///
/// Abre el micrófono en streaming PCM16 mono 16 kHz (`record.startStream`),
/// alimenta cada lote a la [WakeWordPipeline] y avisa por `onDeteccion` cuando
/// se reconoce la palabra. NO compite por el micro con el modo manos libres:
/// el controller lo suelta (`detener`) antes de entrar a manos libres y lo
/// retoma (`iniciar`) al volver.
///
/// El backend de inferencia se inyecta para poder testear con un fake; por
/// defecto usa la cadena ONNX real.
class WakeWordService implements WakeWordEscucha {
  WakeWordService({
    WakeWordBackend? backend,
    AudioRecorder? recorder,
    WakeWordCrumbs? crumbs,
  })  : _backend = backend ?? OnnxWakeWordBackend(),
        _recorder = recorder ?? AudioRecorder(),
        _crumbs = crumbs ?? WakeWordCrumbs();

  final WakeWordBackend _backend;
  final AudioRecorder _recorder;
  final WakeWordCrumbs _crumbs;

  WakeWordPipeline? _pipeline;
  StreamSubscription<Uint8List>? _sub;
  bool _activo = false;
  bool _procesando = false;

  @override
  bool get activo => _activo;

  /// Pide permiso de micrófono. Lanza [PermisoWakeWordDenegado] si se niega.
  Future<void> asegurarPermiso() async {
    final estado = await Permission.microphone.request();
    if (!estado.isGranted) {
      throw PermisoWakeWordDenegado(estado.isPermanentlyDenied);
    }
  }

  /// Arranca la escucha. `umbral` configura la sensibilidad. `onDeteccion` se
  /// invoca (una vez por disparo, con su refractario) al reconocer la palabra.
  ///
  /// Cada paso va logueado y envuelto: si algo CATCHABLE falla, deja todo
  /// limpio (mic parado, `_activo=false`) y relanza para que el controller
  /// muestre el estado de error — nunca a medias.
  void Function(double score)? _onScore;

  @override
  Future<void> iniciar({
    required double umbral,
    required void Function() onDeteccion,
    void Function(double score)? onScore,
  }) async {
    if (_activo) {
      wlog('iniciar(): ya estaba activo, ignoro');
      return;
    }
    _onScore = onScore;
    var arranqueMic = false;
    // Preparamos el archivo de migajas ANTES de cualquier paso nativo, para que
    // las marcas síncronas funcionen aunque lo que siga muera de golpe.
    await _crumbs.preparar();
    try {
      _crumbs.marca('permiso');
      wlog('iniciar(): paso 1/4 — pidiendo permiso de micrófono…');
      await asegurarPermiso();
      wlog('iniciar(): permiso OK');

      wlog('iniciar(): paso 2/4 — cargando modelos ONNX…');
      _crumbs.marca('cargar');
      // El backend escribe una migaja por modelo (sesion:mel/embedding/...).
      await _backend.cargar(migaja: _crumbs.marca);
      _pipeline = WakeWordPipeline(_backend, umbral: umbral);
      wlog('iniciar(): pipeline lista (umbral $umbral)');

      wlog('iniciar(): paso 3/4 — abriendo stream de micrófono…');
      _crumbs.marca('mic-start');
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      arranqueMic = true;
      _activo = true;
      _primerFrame = true;
      _primeraInferencia = true;
      // Pasó toda la activación sin morir: estado seguro.
      _crumbs.marca('escuchando-ok');
      // El callback nunca relanza (todo el cuerpo va en try/catch) y le
      // colgamos un catchError por si el Future async emitiera un error: así
      // un fallo de inferencia jamás escapa a la zona y tumba el proceso.
      _sub = stream.listen(
        (bytes) {
          unawaited(_alimentar(bytes, onDeteccion).catchError((Object e) {
            wlog('error no atrapado en _alimentar: $e');
          }));
        },
        onError: (Object e) => wlog('error del stream de micro: $e'),
        cancelOnError: false,
      );
      wlog('iniciar(): paso 4/4 — escuchando');
    } catch (e) {
      wlog('iniciar(): FALLÓ → $e');
      // Limpieza: que no quede el micro abierto ni el estado a medias.
      _activo = false;
      if (arranqueMic) {
        try {
          await _recorder.stop();
        } catch (_) {}
      }
      rethrow;
    }
  }

  bool _primerFrame = false;
  bool _primeraInferencia = false;

  Future<void> _alimentar(Uint8List bytes, void Function() onDeteccion) async {
    final p = _pipeline;
    if (!_activo || p == null) return;
    if (_primerFrame) {
      _primerFrame = false;
      _crumbs.marca('primer-frame');
      wlog('primer frame de audio recibido (${bytes.length} bytes)');
    }
    // Si una inferencia previa aún corre, soltamos este lote: el wake word
    // tolera huecos cortos y así nunca encolamos trabajo (evita que el micro
    // se "trabe" si un tick tarda).
    if (_procesando) return;
    _procesando = true;
    try {
      // Migaja solo de la PRIMERA inferencia (la que primero cruza al nativo
      // mel/embedding). No escribimos por frame: sería desgaste de disco.
      if (_primeraInferencia) _crumbs.marca('inferencia');
      final detecto = await p.alimentarPcm(bytes);
      if (_primeraInferencia) {
        _primeraInferencia = false;
        _crumbs.marca('inferencia-ok');
      }
      // Reporta el score de cada inferencia (la UI lo muestra y lo loguea
      // throttle-ado en el controller) para ver si "hey jarvis" cruza el umbral.
      _onScore?.call(p.ultimoScore);
      if (detecto && _activo) {
        wlog('DETECTADO score=${p.ultimoScore.toStringAsFixed(3)} → disparando manos libres');
        onDeteccion();
      }
    } catch (e) {
      wlog('error en inferencia (lote descartado): $e');
    } finally {
      _procesando = false;
    }
  }

  /// Suelta el micrófono y para la escucha. Idempotente. Conserva los modelos
  /// cargados para que retomar sea rápido; usa [liberar] para soltarlos.
  @override
  Future<void> detener() async {
    if (_activo) wlog('detener(): soltando micro');
    // Cierre limpio: migaja segura, así un reinicio no lo confunde con muerte.
    _crumbs.marca('apagado');
    _activo = false;
    await _sub?.cancel();
    _sub = null;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (e) {
      wlog('error deteniendo micro: $e');
    }
    _pipeline?.reiniciar();
  }

  /// Libera por completo (micro + modelos ONNX). Para el dispose final.
  @override
  Future<void> liberar() async {
    await detener();
    await _backend.liberar();
    try {
      await _recorder.dispose();
    } catch (_) {}
  }
}
