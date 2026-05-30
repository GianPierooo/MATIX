import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/repaso_repository.dart';

final repasoRepositoryProvider = Provider<RepasoRepository>(
  (ref) => RepasoRepository(ref.watch(matixClientProvider)),
);

/// Repaso de la semana. Se recalcula al entrar a la pantalla; se
/// invalida con `ref.invalidate` para reintentar.
final repasoSemanalProvider = FutureProvider<RepasoSemanal>(
  (ref) => ref.watch(repasoRepositoryProvider).obtener(),
);
