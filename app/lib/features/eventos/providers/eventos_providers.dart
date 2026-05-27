import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notificaciones_service.dart';
import '../../../core/providers.dart';
import '../data/eventos_repository.dart';
import '../domain/evento.dart';

final eventosRepositoryProvider = Provider<EventosRepository>((ref) {
  return EventosRepository(
    ref.watch(matixClientProvider),
    ref.watch(notificacionesServiceProvider),
  );
});

final eventosProvider = FutureProvider<List<Evento>>((ref) async {
  return ref.watch(eventosRepositoryProvider).listar();
});

/// Eventos que ocurren en `dia` (solo fecha, no hora).
final eventosDelDiaProvider =
    Provider.family<AsyncValue<List<Evento>>, DateTime>((ref, dia) {
  final base = ref.watch(eventosProvider);
  return base.whenData((todos) {
    final lista = todos.where((e) => e.ocurreEn(dia)).toList()
      ..sort((a, b) => a.iniciaEn.compareTo(b.iniciaEn));
    return lista;
  });
});
