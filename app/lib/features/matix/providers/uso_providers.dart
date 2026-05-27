import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/uso_repository.dart';

final usoRepositoryProvider = Provider<UsoRepository>((ref) {
  return UsoRepository(ref.watch(matixClientProvider));
});

/// Snapshot del medidor. Se refresca automáticamente tras cada turno
/// del chat (el chat notifier invalida este provider). La franja
/// arriba del chat lo `watch`-ea.
final usoSnapshotProvider = FutureProvider<UsoSnapshot>((ref) async {
  final repo = ref.watch(usoRepositoryProvider);
  return repo.obtener();
});
