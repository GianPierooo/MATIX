import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/despertar_prefs.dart';
import '../data/horario_repository.dart';
import '../domain/plan_dia.dart';

final horarioRepositoryProvider = Provider<HorarioRepository>((ref) {
  return HorarioRepository(ref.watch(matixClientProvider));
});

/// Persistencia de "Me acabo de levantar" (local).
final despertarPrefsProvider = Provider<DespertarPrefs>((ref) => DespertarPrefs());

/// `true` si el despertar de HOY ya está registrado → el botón se oculta el
/// resto del día y reaparece mañana (fecha nueva). Se relee al invalidar (tras
/// marcar el despertar). Best-effort: ante cualquier fallo, muestra el botón.
final despertarHoyProvider = FutureProvider<bool>((ref) async {
  try {
    final fecha = await ref.watch(despertarPrefsProvider).leerFecha();
    return despertarRegistradoHoy(fecha, DateTime.now());
  } catch (_) {
    return false;
  }
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
