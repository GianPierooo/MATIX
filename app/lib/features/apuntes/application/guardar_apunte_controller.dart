import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../matix/data/captura_apunte_repository.dart';
import '../../matix/providers/captura_apunte_providers.dart';
import '../providers/apuntes_providers.dart';

/// Fases de "guardar como apunte" desde el texto OCR de una foto
/// (Capa 7 — unificación del OCR a on-device):
///
/// `inicial`: el usuario está corrigiendo el texto, aún no confirma.
/// `guardando`: el texto viaja al cerebro para clasificarse y crearse.
/// `guardado`: quedó creado; `resultado` trae dónde se archivó.
/// `error`: falló; `error` trae el mensaje + reintento.
enum FaseGuardarApunte { inicial, guardando, guardado, error }

@immutable
class EstadoGuardarApunte {
  const EstadoGuardarApunte({
    this.fase = FaseGuardarApunte.inicial,
    this.resultado,
    this.error,
  });

  final FaseGuardarApunte fase;

  /// El apunte clasificado que devolvió el cerebro (solo en `guardado`).
  final ApunteCapturado? resultado;

  /// Mensaje de error visible (solo en `error`).
  final String? error;

  EstadoGuardarApunte copyWith({
    FaseGuardarApunte? fase,
    ApunteCapturado? resultado,
    Object? error = _kSentinel,
  }) {
    return EstadoGuardarApunte(
      fase: fase ?? this.fase,
      resultado: resultado ?? this.resultado,
      error: identical(error, _kSentinel) ? this.error : error as String?,
    );
  }

  static const _kSentinel = Object();
}

/// Toma el texto que ML Kit extrajo on-device (ya corregido por el
/// usuario en la pantalla editable) y lo guarda como apunte reusando
/// EXACTAMENTE el flujo del Paso C: `POST /matix/capturar-apunte`, que
/// clasifica la nota en proyecto / curso / general. La imagen nunca
/// sale del teléfono — aquí solo viaja el texto.
class GuardarApunteController extends Notifier<EstadoGuardarApunte> {
  @override
  EstadoGuardarApunte build() => const EstadoGuardarApunte();

  /// Guarda `texto` como apunte clasificado. Deja el estado en
  /// `guardado` (con `resultado`) o en `error` con un mensaje y la
  /// opción de reintentar.
  Future<void> guardar(String texto) async {
    final limpio = texto.trim();
    if (limpio.isEmpty) {
      state = const EstadoGuardarApunte(
        fase: FaseGuardarApunte.error,
        error: 'No hay texto que guardar. Escribe o captura algo primero.',
      );
      return;
    }
    if (state.fase == FaseGuardarApunte.guardando) return;

    state = const EstadoGuardarApunte(fase: FaseGuardarApunte.guardando);
    try {
      final apunte =
          await ref.read(capturaApunteRepoProvider).capturar(limpio);
      // Refrescamos la lista de Apuntes (y el "Hoy" de Inicio) para que
      // el recién creado aparezca al instante.
      ref.invalidate(apuntesListProvider);
      state = EstadoGuardarApunte(
        fase: FaseGuardarApunte.guardado,
        resultado: apunte,
      );
    } on MatixApiException catch (e) {
      state = EstadoGuardarApunte(
        fase: FaseGuardarApunte.error,
        error: 'No pude guardar el apunte: ${e.message}',
      );
    } catch (e) {
      state = EstadoGuardarApunte(
        fase: FaseGuardarApunte.error,
        error: 'No pude guardar el apunte: $e',
      );
    }
  }

  void reiniciar() => state = const EstadoGuardarApunte();
}

final guardarApunteControllerProvider =
    NotifierProvider<GuardarApunteController, EstadoGuardarApunte>(
        GuardarApunteController.new);
