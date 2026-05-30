import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../../core/providers.dart';
import '../../finanzas/domain/movimiento.dart';
import '../../finanzas/providers/movimientos_providers.dart';
import '../data/extraccion_recibo_repository.dart';
import '../domain/recibo_propuesto.dart';

/// Fases del flujo recibo → gasto (Finanzas-2):
///
/// `inicial`: aún no se mandó nada al cerebro.
/// `interpretando`: el cerebro está extrayendo monto/fecha/comercio.
/// `revision`: llegó la propuesta; el usuario la edita y confirma.
/// `creando`: confirmó — estamos guardando el gasto en Finanzas.
/// `creado`: el gasto quedó guardado; fin del flujo.
/// `error`: falló la interpretación; `error` trae el mensaje + reintento.
enum FaseRecibo { inicial, interpretando, revision, creando, creado, error }

@immutable
class EstadoRecibo {
  const EstadoRecibo({
    this.fase = FaseRecibo.inicial,
    this.propuesta,
    this.error,
  });

  final FaseRecibo fase;
  final ReciboPropuesto? propuesta;
  final String? error;

  EstadoRecibo copyWith({
    FaseRecibo? fase,
    Object? propuesta = _kSentinel,
    Object? error = _kSentinel,
  }) {
    return EstadoRecibo(
      fase: fase ?? this.fase,
      propuesta: identical(propuesta, _kSentinel)
          ? this.propuesta
          : propuesta as ReciboPropuesto?,
      error: identical(error, _kSentinel) ? this.error : error as String?,
    );
  }

  static const _kSentinel = Object();
}

/// Orquesta interpretar → revisar → guardar. El texto se interpreta una
/// vez (el cerebro propone monto/fecha/comercio/categoría); la hoja de
/// revisión edita los valores localmente; al confirmar se crea UN gasto
/// con el `MovimientosRepository` de Finanzas-1 y se invalida la lista
/// para que aparezca al instante en Finanzas e Inicio.
class ExtraccionReciboController extends Notifier<EstadoRecibo> {
  @override
  EstadoRecibo build() => const EstadoRecibo();

  Future<void> interpretar(String texto) async {
    final limpio = texto.trim();
    if (limpio.isEmpty) {
      state = const EstadoRecibo(
        fase: FaseRecibo.error,
        error: 'No hay texto que leer. Escribe o captura un recibo primero.',
      );
      return;
    }
    state = const EstadoRecibo(fase: FaseRecibo.interpretando);
    try {
      final propuesta =
          await ref.read(extraccionReciboRepositoryProvider).extraer(limpio);
      state = EstadoRecibo(fase: FaseRecibo.revision, propuesta: propuesta);
    } on MatixApiException catch (e) {
      state = EstadoRecibo(
        fase: FaseRecibo.error,
        error: 'No pude leer el recibo: ${e.message}',
      );
    } catch (e) {
      state = EstadoRecibo(
        fase: FaseRecibo.error,
        error: 'No pude leer el recibo: $e',
      );
    }
  }

  /// Guarda el gasto en Finanzas con los valores ya revisados. El monto
  /// debe ser positivo: no inventamos cifras. Al terminar bien, invalida
  /// la lista de movimientos para refrescar Finanzas e Inicio.
  Future<void> crear({
    required double monto,
    required String categoria,
    required DateTime fecha,
    String nota = '',
  }) async {
    if (state.fase == FaseRecibo.creando) return;
    if (monto <= 0) {
      state = state.copyWith(
        fase: FaseRecibo.revision,
        error: 'Pon un monto mayor que 0.',
      );
      return;
    }
    state = state.copyWith(fase: FaseRecibo.creando, error: null);
    try {
      await ref.read(movimientosRepoProvider).crear(
            tipo: TipoMovimiento.gasto,
            monto: monto,
            categoria: categoria.trim().isEmpty ? 'Otros' : categoria.trim(),
            fecha: fecha,
            nota: nota.trim(),
          );
      ref.invalidate(movimientosListProvider);
      state = state.copyWith(fase: FaseRecibo.creado);
    } on MatixApiException catch (e) {
      state = state.copyWith(
        fase: FaseRecibo.revision,
        error: 'No pude guardar el gasto: ${e.message}',
      );
    } catch (e) {
      state = state.copyWith(
        fase: FaseRecibo.revision,
        error: 'No pude guardar el gasto: $e',
      );
    }
  }

  void reiniciar() => state = const EstadoRecibo();
}

final extraccionReciboRepositoryProvider =
    Provider<ExtraccionReciboRepository>((ref) {
  return ExtraccionReciboRepository(ref.watch(matixClientProvider));
});

final extraccionReciboControllerProvider =
    NotifierProvider<ExtraccionReciboController, EstadoRecibo>(
        ExtraccionReciboController.new);
