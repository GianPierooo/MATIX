import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// El usuario negó el permiso de micrófono al grabar muestras.
class PermisoMicMuestrasDenegado implements Exception {
  PermisoMicMuestrasDenegado(this.permanente);

  /// `true` si marcó "no preguntar más" → hay que mandarlo a Ajustes.
  final bool permanente;
}

/// Graba clips cortos para el entrenamiento del wake word en el formato EXACTO
/// que pide openWakeWord: **WAV PCM 16-bit, 16 kHz, mono**. (El pipeline de
/// chat usa m4a/AAC para Whisper; aquí necesitamos WAV crudo para entrenar.)
///
/// Uso: `iniciar()` arranca la captura; `detener()` la cierra y devuelve el
/// archivo .wav. `cancelar()` aborta y borra el temporal.
class WakeWordMuestrasGrabador {
  WakeWordMuestrasGrabador({AudioRecorder? recorder})
      : _rec = recorder ?? AudioRecorder();

  final AudioRecorder _rec;
  String? _ruta;

  bool _grabando = false;
  bool get grabando => _grabando;

  Future<void> iniciar() async {
    final estado = await Permission.microphone.request();
    if (!estado.isGranted) {
      throw PermisoMicMuestrasDenegado(estado.isPermanentlyDenied);
    }
    if (await _rec.isRecording()) {
      await _rec.stop();
    }
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    _ruta = '${dir.path}/oye_matix_muestra_$ts.wav';
    await _rec.start(
      const RecordConfig(
        // WAV = PCM 16-bit sin comprimir. 16 kHz mono: lo que consume la
        // cadena ONNX de openWakeWord sin reconversión.
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _ruta!,
    );
    _grabando = true;
  }

  /// Cierra la grabación y devuelve el .wav (o `null` si no había nada).
  Future<File?> detener() async {
    if (!_grabando) return null;
    _grabando = false;
    final ruta = _ruta;
    final ret = await _rec.stop();
    final pathFinal = ret ?? ruta;
    _ruta = null;
    if (pathFinal == null) return null;
    final f = File(pathFinal);
    if (!await f.exists()) return null;
    return f;
  }

  Future<void> cancelar() async {
    final ruta = _ruta;
    _ruta = null;
    _grabando = false;
    if (await _rec.isRecording()) {
      await _rec.stop();
    }
    if (ruta != null) {
      final f = File(ruta);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {
          // best-effort; los temporales se limpian solos.
        }
      }
    }
  }

  Future<void> dispose() async {
    await cancelar();
    await _rec.dispose();
  }
}
