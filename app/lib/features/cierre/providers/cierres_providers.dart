import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/cierres_repository.dart';
import '../domain/cierre_dia.dart';

final cierresRepoProvider = Provider<CierresRepository>(
  (ref) => CierresRepository(ref.watch(matixClientProvider)),
);

final cierresListProvider = FutureProvider<List<CierreDia>>(
  (ref) => ref.watch(cierresRepoProvider).listar(),
);

/// Cierre del día indicado (o `null` si todavía no se hizo).
final cierreDeFechaProvider =
    FutureProvider.family<CierreDia?, DateTime>((ref, fecha) async {
  // Buscar por fecha exacta. Usamos solo año/mes/día.
  final fechaSolo = DateTime(fecha.year, fecha.month, fecha.day);
  return ref.watch(cierresRepoProvider).obtenerDe(fechaSolo);
});
