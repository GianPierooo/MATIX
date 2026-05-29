import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notificaciones_service.dart';
import '../../../core/providers.dart';
import '../data/eventos_repository.dart';
import '../domain/evento.dart';
import '../domain/recurrencia.dart';

final eventosRepositoryProvider = Provider<EventosRepository>((ref) {
  return EventosRepository(
    ref.watch(matixClientProvider),
    ref.watch(notificacionesServiceProvider),
  );
});

final eventosProvider = FutureProvider<List<Evento>>((ref) async {
  return ref.watch(eventosRepositoryProvider).listar();
});

/// Eventos que ocurren en `dia` (solo fecha, no hora). Para series recurrentes
/// devuelve una ocurrencia desplazada por cada vez que la regla cae ese día
/// (vía `copyConInicio`); para eventos únicos, el evento tal cual.
final eventosDelDiaProvider =
    Provider.family<AsyncValue<List<Evento>>, DateTime>((ref, dia) {
  final base = ref.watch(eventosProvider);
  return base.whenData((todos) {
    final lista = <Evento>[];
    for (final e in todos) {
      final regla = e.regla;
      if (regla == null) {
        if (e.ocurreEn(dia)) lista.add(e);
        continue;
      }
      final ocurrencias = ocurrenciasEnDia(
        regla: regla,
        inicioSerie: e.iniciaEn.toLocal(),
        dia: dia,
      );
      for (final occ in ocurrencias) {
        lista.add(e.copyConInicio(occ.toUtc()));
      }
    }
    lista.sort((a, b) => a.iniciaEn.compareTo(b.iniciaEn));
    return lista;
  });
});
