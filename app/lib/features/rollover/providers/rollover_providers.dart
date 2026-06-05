import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/rollover_repository.dart';
import '../domain/rollover.dart';

final rolloverRepositoryProvider = Provider<RolloverRepository>(
  (ref) => RolloverRepository(ref.watch(matixClientProvider)),
);

/// Propuestas de rollover + sobrecarga. Se cachea hasta invalidar (tras decidir
/// o refrescar). El robot lo lee para surfacear lo no cumplido tocable. Si el
/// cerebro no responde, la vista cae a `valueOrNull == null` sin romper.
final rolloverProvider = FutureProvider<RolloverData>((ref) async {
  return ref.watch(rolloverRepositoryProvider).cargar();
});
