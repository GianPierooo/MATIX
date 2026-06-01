import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'wakeword_pipeline.dart';

/// Implementación real de [WakeWordBackend] con la cadena ONNX de openWakeWord
/// (melspectrograma → embedding → clasificador) corriendo on-device vía
/// `flutter_onnxruntime`.
///
/// Las tres sesiones se mantienen vivas mientras el escuchador está activo. El
/// trabajo nativo corre por method channel (fuera del hilo de UI de Dart), así
/// que las ~12.5 inferencias/s no traban la interfaz. Cada `OrtValue` se libera
/// tras usarse para no fugar memoria nativa.
class OnnxWakeWordBackend implements WakeWordBackend {
  OnnxWakeWordBackend({
    this.dirAssets = 'assets/models/wakeword',
    this.archivoClasificador = 'hey_jarvis_v0.1.onnx',
  });

  /// Carpeta de assets donde viven los .onnx.
  final String dirAssets;

  /// Nombre del modelo clasificador. Para pasar de "hey jarvis" a "oye matix"
  /// solo se reemplaza este archivo (la cadena compartida no cambia).
  final String archivoClasificador;

  final OnnxRuntime _ort = OnnxRuntime();
  OrtSession? _mel;
  OrtSession? _emb;
  OrtSession? _clf;

  @override
  Future<void> cargar() async {
    _mel = await _ort.createSessionFromAsset('$dirAssets/melspectrogram.onnx');
    _emb = await _ort.createSessionFromAsset('$dirAssets/embedding_model.onnx');
    _clf = await _ort.createSessionFromAsset('$dirAssets/$archivoClasificador');
  }

  @override
  Future<List<Float32List>> melspectrograma(Float32List muestras) async {
    final s = _mel!;
    final entrada = await OrtValue.fromList(muestras, [1, muestras.length]);
    try {
      final salida = await s.run({s.inputNames.first: entrada});
      final t = salida[s.outputNames.first]!;
      try {
        // Forma [time, 1, frames, 32]; en streaming time=1, así que el plano
        // es frames*32 en orden row-major.
        final plano = (await t.asFlattenedList()).cast<num>();
        final frames = <Float32List>[];
        const bins = WakeWordPipeline.kBinsMel;
        for (var i = 0; i + bins <= plano.length; i += bins) {
          final f = Float32List(bins);
          for (var j = 0; j < bins; j++) {
            // Transformación de openWakeWord: x/10 + 2.
            f[j] = plano[i + j].toDouble() / 10.0 + 2.0;
          }
          frames.add(f);
        }
        return frames;
      } finally {
        await _liberarSalida(salida);
      }
    } finally {
      await entrada.dispose();
    }
  }

  @override
  Future<Float32List> embedding(List<Float32List> ventana76) async {
    final s = _emb!;
    const bins = WakeWordPipeline.kBinsMel;
    const filas = WakeWordPipeline.kVentanaMel;
    final plano = Float32List(filas * bins);
    for (var i = 0; i < filas; i++) {
      final fila = ventana76[i];
      for (var j = 0; j < bins; j++) {
        plano[i * bins + j] = fila[j];
      }
    }
    // El embedding pide [n, 76, 32, 1].
    final entrada = await OrtValue.fromList(plano, [1, filas, bins, 1]);
    try {
      final salida = await s.run({s.inputNames.first: entrada});
      final t = salida[s.outputNames.first]!;
      try {
        final plano = (await t.asFlattenedList()).cast<num>();
        final out = Float32List(plano.length);
        for (var i = 0; i < plano.length; i++) {
          out[i] = plano[i].toDouble();
        }
        return out;
      } finally {
        await _liberarSalida(salida);
      }
    } finally {
      await entrada.dispose();
    }
  }

  @override
  Future<double> clasificar(List<Float32List> ventana16) async {
    final s = _clf!;
    const dim = 96;
    const filas = WakeWordPipeline.kVentanaFeatures;
    final plano = Float32List(filas * dim);
    for (var i = 0; i < filas; i++) {
      final fila = ventana16[i];
      for (var j = 0; j < dim; j++) {
        plano[i * dim + j] = fila[j];
      }
    }
    // El clasificador pide [1, 16, 96].
    final entrada = await OrtValue.fromList(plano, [1, filas, dim]);
    try {
      final salida = await s.run({s.inputNames.first: entrada});
      final t = salida[s.outputNames.first]!;
      try {
        final plano = (await t.asFlattenedList()).cast<num>();
        return plano.isEmpty ? 0.0 : plano.first.toDouble();
      } finally {
        await _liberarSalida(salida);
      }
    } finally {
      await entrada.dispose();
    }
  }

  Future<void> _liberarSalida(Map<String, OrtValue> salida) async {
    for (final v in salida.values) {
      try {
        await v.dispose();
      } catch (_) {
        // Liberar es best-effort; no debe romper el bucle de detección.
      }
    }
  }

  @override
  Future<void> liberar() async {
    for (final s in [_mel, _emb, _clf]) {
      try {
        await s?.close();
      } catch (e) {
        if (kDebugMode) debugPrint('WakeWord: error cerrando sesión ONNX: $e');
      }
    }
    _mel = null;
    _emb = null;
    _clf = null;
  }
}
