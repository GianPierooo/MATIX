import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'wakeword_log.dart';
import 'wakeword_modelo.dart';
import 'wakeword_pipeline.dart';

/// Falla controlada al cargar/usar un modelo ONNX. Lleva el nombre del modelo
/// para que el estado de error y los logs digan EXACTAMENTE cuál reventó.
class WakeWordOnnxError implements Exception {
  WakeWordOnnxError(this.paso, this.causa);
  final String paso;
  final Object causa;
  @override
  String toString() => 'WakeWordOnnxError($paso): $causa';
}

/// Implementación real de [WakeWordBackend] con la cadena ONNX de openWakeWord
/// (melspectrograma → embedding → clasificador) corriendo on-device vía
/// `flutter_onnxruntime`.
///
/// Robustez (esta cadena corre por 1ra vez en hardware real al activar la
/// palabra):
/// - Carga IDEMPOTENTE y por-sesión: si ya está cargada no recrea nada (antes
///   `iniciar` llamaba `cargar` en cada arranque/relevo y fugaba sesiones).
/// - Sesiones forzadas a CPU + 1 hilo intra-op: lo más compatible y liviano en
///   gama baja (evita rutas NNAPI/XNNPACK y pools de hilos que pueden tronar).
/// - Cada paso envuelto en try/catch y logueado. Un fallo CATCHABLE se traduce
///   en [WakeWordOnnxError] (→ estado error visible, sin tumbar la app). Un
///   crash NATIVO (SIGSEGV) no se puede atrapar desde Dart, pero el log deja
///   ver el último paso vivo.
class OnnxWakeWordBackend implements WakeWordBackend {
  OnnxWakeWordBackend({
    this.dirAssets = 'assets/models/wakeword',
    this.archivoClasificador = WakeWordModelo.archivo,
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

  // Sesiones a CPU + 1 hilo: estable y suficiente para modelos diminutos.
  OrtSessionOptions get _opts =>
      OrtSessionOptions(providers: [OrtProvider.CPU], intraOpNumThreads: 1);

  @override
  Future<void> cargar({void Function(String paso)? migaja}) async {
    // Idempotente: solo crea lo que falte (no refabrica ni fuga).
    if (_mel != null && _emb != null && _clf != null) {
      wlog('cargar(): ya cargado, no recreo sesiones');
      return;
    }
    // La migaja se escribe ANTES de cada createSession: si el proceso muere de
    // golpe al crear esa sesión (p.ej. la lib nativa al cargarse), el rastro en
    // disco dice exactamente cuál.
    if (_mel == null) {
      migaja?.call('sesion:mel');
      _mel = await _crearSesion('melspectrogram.onnx', 'melspectrograma');
    }
    if (_emb == null) {
      migaja?.call('sesion:embedding');
      _emb = await _crearSesion('embedding_model.onnx', 'embedding');
    }
    if (_clf == null) {
      migaja?.call('sesion:clasificador');
      _clf = await _crearSesion(archivoClasificador, 'clasificador');
    }
    wlog('cargar(): las 3 sesiones ONNX listas');
  }

  Future<OrtSession> _crearSesion(String archivo, String etiqueta) async {
    final assetKey = '$dirAssets/$archivo';
    try {
      // 1) Confirmar que el asset existe y se puede leer (error catchable de
      //    Dart, NO crash nativo). Logueamos el tamaño para verificar que no
      //    llegó truncado.
      final bytes = await rootBundle.load(assetKey);
      wlog('sesion[$etiqueta]: asset $archivo cargado (${bytes.lengthInBytes} bytes), creando sesión…');
      // 2) Crear la sesión ONNX (esto cruza al nativo; un modelo corrupto o un
      //    ORT incompatible podría tronar aquí — el log de arriba es la última
      //    pista si muere).
      final s = await _ort.createSessionFromAsset(assetKey, options: _opts);
      wlog('sesion[$etiqueta]: OK · in=${s.inputNames} out=${s.outputNames}');
      return s;
    } catch (e) {
      wlog('sesion[$etiqueta]: FALLÓ → $e');
      throw WakeWordOnnxError(etiqueta, e);
    }
  }

  bool _logueoPrimerMel = false;
  bool _logueoPrimerEmb = false;
  bool _logueoPrimerClf = false;

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
        if (!_logueoPrimerMel) {
          _logueoPrimerMel = true;
          wlog('1er melspectrograma OK (${frames.length} frames)');
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
        if (!_logueoPrimerEmb) {
          _logueoPrimerEmb = true;
          wlog('1er embedding OK (dim ${out.length})');
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
        final score = plano.isEmpty ? 0.0 : plano.first.toDouble();
        if (!_logueoPrimerClf) {
          _logueoPrimerClf = true;
          wlog('1er clasificador OK (score $score)');
        }
        return score;
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
        wlog('error cerrando sesión ONNX: $e');
      }
    }
    _mel = null;
    _emb = null;
    _clf = null;
  }
}
