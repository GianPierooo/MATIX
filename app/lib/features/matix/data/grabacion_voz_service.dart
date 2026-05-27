import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Configuración de VAD (voice activity detection) para el modo
/// manos libres (Capa 2 Paso 5.1).
///
/// El flujo es de dos fases:
///
/// **Fase 1 — Esperar voz**: tras abrir el micro, polleamos la
/// amplitud. Si el nivel sube por encima de `umbralVozDb` antes de
/// `esperaInicialMaxima`, consideramos que el usuario empezó a
/// hablar y pasamos a la fase 2. Si NO, devolvemos
/// `ResultadoEscucha.sinVoz` — no se manda nada a Whisper.
///
/// **Fase 2 — Esperar silencio**: ahora ya está hablando. Cuando
/// el nivel queda por debajo de `umbralSilencioDb` durante
/// `silencioRequerido` seguido, cortamos y devolvemos el archivo.
class ConfigVad {
  const ConfigVad({
    this.umbralVozDb = -30,
    this.umbralSilencioDb = -40,
    this.esperaInicialMaxima = const Duration(seconds: 6),
    this.silencioRequerido = const Duration(milliseconds: 1300),
    this.duracionMaxima = const Duration(seconds: 60),
    this.intervalo = const Duration(milliseconds: 150),
  });

  /// Nivel mínimo en dBFS para considerar que el usuario está
  /// hablando. La voz humana cerca del mic suele estar en -20…-10.
  final double umbralVozDb;

  /// Nivel por debajo del cual consideramos silencio. Algo más bajo
  /// que `umbralVozDb` para evitar oscilación cerca del umbral.
  final double umbralSilencioDb;

  /// Tiempo máximo esperando la primera voz. Si pasa sin que el
  /// usuario hable, abandonamos (estado "en pausa").
  final Duration esperaInicialMaxima;

  /// Cuánto silencio seguido cuenta como "terminó la frase".
  final Duration silencioRequerido;

  /// Tope absoluto de la grabación entera (fase 1 + fase 2).
  final Duration duracionMaxima;

  /// Cada cuánto se pollea la amplitud.
  final Duration intervalo;
}

/// Razón por la que terminó la escucha.
enum ResultadoEscucha {
  /// El usuario habló y terminó. `GrabacionResultado` válido.
  cortada,

  /// El usuario nunca habló dentro de `esperaInicialMaxima`. No hay
  /// archivo válido — no se manda a Whisper.
  sinVoz,

  /// Se llegó al tope `duracionMaxima`. Hay archivo, igual se manda.
  topeAlcanzado,

  /// El caller llamó `cancelar()` mientras grabamos. Sin archivo.
  cancelada,
}

class EscuchaConVad {
  const EscuchaConVad({
    required this.resultado,
    this.grabacion,
  });
  final ResultadoEscucha resultado;
  final GrabacionResultado? grabacion;
}

/// Resultado de una grabación cuando termina bien.
class GrabacionResultado {
  const GrabacionResultado({required this.archivo, required this.duracion});
  final File archivo;
  final Duration duracion;
}

/// Excepción cuando el usuario deniega el permiso de micrófono.
class PermisoMicDenegado implements Exception {
  PermisoMicDenegado(this.permanente);

  /// `true` si el usuario marcó "no preguntar más" → hay que mandarlo
  /// a Ajustes del sistema para que lo conceda manualmente.
  final bool permanente;
}

/// Captura de audio para la entrada por voz de Matix.
///
/// Encapsula `package:record` y `permission_handler` para que la
/// pantalla solo trate con `iniciar()` / `detener()`. Devuelve un
/// archivo m4a/AAC listo para subir a `/matix/transcribir`.
///
/// Reglas:
/// - `iniciar()` pide permiso si hace falta. Lanza
///   `PermisoMicDenegado` si el usuario lo niega.
/// - `iniciar()` borra cualquier grabación previa sobre la marcha
///   (idempotente).
/// - `detener()` cierra el recorder y devuelve el archivo + la
///   duración. Si todavía no había `iniciar()` exitoso, devuelve
///   `null`.
/// - `cancelar()` aborta sin devolver archivo y borra el temporal.
/// - `dispose()` libera recursos al cerrar la pantalla.
class GrabacionVozService {
  GrabacionVozService();

  final _recorder = AudioRecorder();

  String? _rutaActual;
  DateTime? _inicioActual;

  bool get estaGrabando => _inicioActual != null;

  Future<void> iniciar() async {
    // Permiso runtime
    final estado = await Permission.microphone.request();
    if (!estado.isGranted) {
      throw PermisoMicDenegado(estado.isPermanentlyDenied);
    }

    // Si por alguna razón el recorder quedó vivo de una sesión
    // previa, lo detenemos antes de empezar la nueva.
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }

    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    _rutaActual = '${dir.path}/matix_voz_$ts.m4a';

    await _recorder.start(
      const RecordConfig(
        // AAC en contenedor m4a: estándar Android, soportado por
        // Whisper, ~16 KB/s a 32 kbps para voz limpia.
        encoder: AudioEncoder.aacLc,
        bitRate: 32000,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _rutaActual!,
    );
    _inicioActual = DateTime.now();
  }

  Future<GrabacionResultado?> detener() async {
    if (_inicioActual == null) return null;
    final inicio = _inicioActual!;
    final ruta = _rutaActual;
    _inicioActual = null;
    _rutaActual = null;

    final ret = await _recorder.stop();
    final pathFinal = ret ?? ruta;
    if (pathFinal == null) return null;

    final archivo = File(pathFinal);
    if (!await archivo.exists()) return null;
    return GrabacionResultado(
      archivo: archivo,
      duracion: DateTime.now().difference(inicio),
    );
  }

  Future<void> cancelar() async {
    final ruta = _rutaActual;
    _inicioActual = null;
    _rutaActual = null;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    if (ruta != null) {
      final f = File(ruta);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {
          // No es crítico — los temp se limpian solos eventualmente.
        }
      }
    }
  }

  Future<void> dispose() async {
    await cancelar();
    await _recorder.dispose();
  }

  /// Escucha con VAD de dos fases (Capa 2 Paso 5.1):
  ///
  /// 1. Espera a que el usuario empiece a hablar (amplitud sobre
  ///    `umbralVozDb`). Si no pasa nada en `esperaInicialMaxima`,
  ///    devuelve `ResultadoEscucha.sinVoz` y nada va a Whisper.
  /// 2. Una vez que arrancó la voz, sigue grabando hasta que haya
  ///    `silencioRequerido` de silencio seguido, o se llegue al
  ///    `duracionMaxima` tope.
  ///
  /// `onAmplitud` recibe el nivel en dBFS en cada poll — útil para
  /// dibujar una onda visual en la UI.
  Future<EscuchaConVad> escucharConVad({
    ConfigVad config = const ConfigVad(),
    void Function(double db)? onAmplitud,
  }) async {
    if (estaGrabando) {
      await cancelar();
    }
    await iniciar(); // puede lanzar PermisoMicDenegado

    final inicio = _inicioActual!;
    bool empezoAHablar = false;
    Duration silencioAcumulado = Duration.zero;
    final completer = Completer<ResultadoEscucha>();

    final timer = Timer.periodic(config.intervalo, (_) async {
      if (completer.isCompleted) return;
      final amp = await _recorder.getAmplitude();
      final db = amp.current;
      onAmplitud?.call(db);

      final transcurrido = DateTime.now().difference(inicio);

      // Tope absoluto
      if (transcurrido >= config.duracionMaxima) {
        if (!completer.isCompleted) {
          completer.complete(
            empezoAHablar
                ? ResultadoEscucha.topeAlcanzado
                : ResultadoEscucha.sinVoz,
          );
        }
        return;
      }

      if (!empezoAHablar) {
        // Fase 1: esperando primera voz
        if (db >= config.umbralVozDb) {
          empezoAHablar = true;
          silencioAcumulado = Duration.zero;
          return;
        }
        if (transcurrido >= config.esperaInicialMaxima) {
          if (!completer.isCompleted) {
            completer.complete(ResultadoEscucha.sinVoz);
          }
        }
        return;
      }

      // Fase 2: ya está hablando, esperar silencio sostenido
      if (db < config.umbralSilencioDb) {
        silencioAcumulado += config.intervalo;
        if (silencioAcumulado >= config.silencioRequerido) {
          if (!completer.isCompleted) {
            completer.complete(ResultadoEscucha.cortada);
          }
        }
      } else {
        silencioAcumulado = Duration.zero;
      }
    });

    final ResultadoEscucha resultado;
    try {
      resultado = await completer.future;
    } finally {
      timer.cancel();
    }

    if (resultado == ResultadoEscucha.sinVoz) {
      // No hubo voz — tiramos el audio capturado (es solo silencio
      // de fondo).
      await cancelar();
      return const EscuchaConVad(resultado: ResultadoEscucha.sinVoz);
    }

    final grab = await detener();
    if (grab == null) {
      return const EscuchaConVad(resultado: ResultadoEscucha.cancelada);
    }
    return EscuchaConVad(resultado: resultado, grabacion: grab);
  }
}
