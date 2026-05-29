import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../data/grabacion_voz_service.dart';
import '../data/matix_transcribir_repository.dart';

/// Estado de la cápsula "grabar + transcribir" del composer del chat.
///
/// Modelo de estados:
///
///     idle          — sin acción; el botón mic está disponible.
///     grabando      — recorder activo; mostramos contador y stop.
///     transcribiendo — audio subido a /matix/transcribir; esperando
///                      respuesta de Whisper.
///     error         — algo falló (permiso denegado, red, 502…).
///
/// Importante: NO controlamos el composer desde acá. Cuando la
/// transcripción llega, la pantalla la lee de `textoTranscrito` (o
/// vía el stream `onTextoListo`) y la inserta en su `TextEditingController`
/// para que el usuario revise y mande él. El paso de "rellenar el
/// input" vive en la UI, no acá.
enum FaseVoz { idle, grabando, transcribiendo, error }

@immutable
class EstadoVoz {
  const EstadoVoz({
    this.fase = FaseVoz.idle,
    this.error,
    this.duracion = Duration.zero,
  });

  final FaseVoz fase;
  final String? error;
  final Duration duracion;

  EstadoVoz copyWith({
    FaseVoz? fase,
    Object? error = _kSentinel,
    Duration? duracion,
  }) {
    return EstadoVoz(
      fase: fase ?? this.fase,
      error:
          identical(error, _kSentinel) ? this.error : error as String?,
      duracion: duracion ?? this.duracion,
    );
  }

  static const _kSentinel = Object();
}

final _grabacionServiceProvider = Provider<GrabacionVozService>((ref) {
  final svc = GrabacionVozService();
  ref.onDispose(() => svc.dispose());
  return svc;
});

final _transcribirRepoProvider = Provider<MatixTranscribirRepository>((ref) {
  final repo = MatixTranscribirRepository();
  ref.onDispose(repo.close);
  return repo;
});

/// Notifier de voz para una pantalla. `autoDispose` para que al
/// salir del chat el recorder se libere y no quede el mic abierto.
final vozNotifierProvider =
    NotifierProvider.autoDispose<VozNotifier, EstadoVoz>(VozNotifier.new);

class VozNotifier extends AutoDisposeNotifier<EstadoVoz> {
  GrabacionVozService get _svc => ref.read(_grabacionServiceProvider);
  MatixTranscribirRepository get _repo =>
      ref.read(_transcribirRepoProvider);

  @override
  EstadoVoz build() => const EstadoVoz();

  /// Empieza a grabar. Si el permiso falta, lo pide. Si lo deniega,
  /// el estado pasa a `error` con un mensaje claro y opcionalmente
  /// la UI ofrece abrir Ajustes (cuando `permanente` es true).
  Future<void> iniciar() async {
    if (state.fase == FaseVoz.grabando ||
        state.fase == FaseVoz.transcribiendo) {
      return;
    }
    try {
      await _svc.iniciar();
      state = const EstadoVoz(fase: FaseVoz.grabando);
    } on PermisoMicDenegado catch (e) {
      state = EstadoVoz(
        fase: FaseVoz.error,
        error: e.permanente
            ? 'No puedo usar el micrófono. Concédeme el permiso desde '
                'los ajustes del sistema y vuelve a intentar.'
            : 'Necesito permiso del micrófono para grabar.',
      );
    } catch (e) {
      state = EstadoVoz(
        fase: FaseVoz.error,
        error: 'No pude empezar a grabar: $e',
      );
    }
  }

  /// Llamado por un `Ticker` o `Timer.periodic` en la UI para
  /// actualizar el contador visible. Mantener el reloj en la UI
  /// (en vez de tener un Timer en el notifier) hace los tests más
  /// fáciles y evita rebuilds innecesarios cuando la pantalla está
  /// detrás de otra.
  void actualizarDuracion(Duration d) {
    if (state.fase != FaseVoz.grabando) return;
    state = state.copyWith(duracion: d);
  }

  /// Para de grabar, sube el archivo, devuelve el texto si fue OK.
  /// Devuelve `null` si la grabación fue muy corta o si hubo error
  /// (el estado del notifier ya reflejará el error en ese caso).
  Future<String?> detenerYTranscribir() async {
    if (state.fase != FaseVoz.grabando) return null;
    state = state.copyWith(fase: FaseVoz.transcribiendo);

    final grab = await _svc.detener();
    if (grab == null) {
      state = const EstadoVoz(
        fase: FaseVoz.error,
        error: 'No quedó nada grabado. Volvé a intentar.',
      );
      return null;
    }
    // Audio muy corto (<0.4 s) → casi seguro un tap accidental.
    // Evitamos pegarle a Whisper para no quemar centavos en silencio.
    if (grab.duracion < const Duration(milliseconds: 400)) {
      state = const EstadoVoz(
        fase: FaseVoz.error,
        error: 'Grabación demasiado corta. Mantené el botón un '
            'instante más.',
      );
      try {
        await grab.archivo.delete();
      } catch (_) {}
      return null;
    }

    try {
      final texto = await _repo.transcribir(grab.archivo);
      state = const EstadoVoz();
      return texto.isEmpty ? null : texto;
    } on MatixApiException catch (e) {
      state = EstadoVoz(
        fase: FaseVoz.error,
        error: _mensajeDeError(e),
      );
      return null;
    } catch (e) {
      state = EstadoVoz(
        fase: FaseVoz.error,
        error: 'Error inesperado al transcribir: $e',
      );
      return null;
    } finally {
      try {
        await grab.archivo.delete();
      } catch (_) {
        // No crítico.
      }
    }
  }

  /// Aborta sin transcribir (usuario tocó la X).
  Future<void> cancelar() async {
    if (state.fase == FaseVoz.transcribiendo) return; // ya está en vuelo
    await _svc.cancelar();
    state = const EstadoVoz();
  }

  /// Limpia el error tras mostrárselo al usuario.
  void limpiarError() {
    if (state.fase == FaseVoz.error) {
      state = const EstadoVoz();
    }
  }
}

String _mensajeDeError(MatixApiException e) {
  if (e.statusCode == 503) {
    return 'La voz no está disponible ahora mismo. (${e.message})';
  }
  if (e.statusCode == 413) {
    return 'El audio quedó muy largo. Hablá un fragmento más corto.';
  }
  if (e.statusCode == 0) {
    return 'No pude llegar al cerebro. ¿Está corriendo?';
  }
  return 'No pude transcribir (${e.statusCode}): ${e.message}';
}
