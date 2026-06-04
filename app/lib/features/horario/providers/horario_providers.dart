import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/horario_repository.dart';
import '../domain/plan_dia.dart';

final horarioRepositoryProvider = Provider<HorarioRepository>((ref) {
  return HorarioRepository(ref.watch(matixClientProvider));
});

/// Si está activo, el plan se trae como REPLAN (resto del día desde ahora).
/// La vista lo enciende con «replanifica» y se resetea al refrescar.
final replanActivoProvider = StateProvider<bool>((ref) => false);

/// El plan del día. Se recalcula al vuelo en el cerebro; acá solo se cachea
/// hasta invalidar (al marcar hecho/saltar/refrescar).
final planDiaProvider = FutureProvider<PlanDia>((ref) async {
  final desdeAhora = ref.watch(replanActivoProvider);
  return ref.watch(horarioRepositoryProvider).cargar(desdeAhora: desdeAhora);
});
