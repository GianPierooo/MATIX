import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/movimientos_repository.dart';
import '../domain/movimiento.dart';

final movimientosRepoProvider = Provider<MovimientosRepository>(
  (ref) => MovimientosRepository(ref.watch(matixClientProvider)),
);

/// Todos los movimientos (más recientes primero). La vista de Finanzas y
/// la tarjeta de Inicio cortan esta lista por mes con los helpers puros
/// del dominio. Se invalida tras crear / editar / borrar.
final movimientosListProvider = FutureProvider<List<Movimiento>>(
  (ref) => ref.watch(movimientosRepoProvider).listar(),
);
