import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'onnx_backend.dart';
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
  })  : _backend = backend ?? OnnxWakeWordBackend(),
        _recorder = recorder ?? AudioRecorder();

  final WakeWordBackend _backend;
  final AudioRecorder _recorder;

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
  @override
  Future<void> iniciar({
    required double umbral,
    required void Function() onDeteccion,
  }) async {
    if (_activo) return;
    await asegurarPermiso();

    // Carga perezosa de los modelos la primera vez.
    await _backend.cargar();
    _pipeline = WakeWordPipeline(_backend, umbral: umbral);

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
    _activo = true;
    _sub = stream.listen(
      (bytes) => _alimentar(bytes, onDeteccion),
      onError: (Object e) {
        if (kDebugMode) debugPrint('WakeWord: error del micro: $e');
      },
      cancelOnError: false,
    );
  }

  Future<void> _alimentar(Uint8List bytes, void Function() onDeteccion) async {
    final p = _pipeline;
    if (!_activo || p == null) return;
    // Si una inferencia previa aún corre, soltamos este lote: el wake word
    // tolera huecos cortos y así nunca encolamos trabajo (evita que el micro
    // se "trabe" si un tick tarda).
    if (_procesando) return;
    _procesando = true;
    try {
      final detecto = await p.alimentarPcm(bytes);
      if (detecto && _activo) {
        onDeteccion();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('WakeWord: error en inferencia: $e');
    } finally {
      _procesando = false;
    }
  }

  /// Suelta el micrófono y para la escucha. Idempotente. Conserva los modelos
  /// cargados para que retomar sea rápido; usa [liberar] para soltarlos.
  @override
  Future<void> detener() async {
    _activo = false;
    await _sub?.cancel();
    _sub = null;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('WakeWord: error deteniendo micro: $e');
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
