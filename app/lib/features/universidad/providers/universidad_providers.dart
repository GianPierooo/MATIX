import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notificaciones_service.dart';
import '../../../core/providers.dart';
import '../../cursos/data/cursos_repository.dart';
import '../../cursos/domain/curso.dart';
import '../../cursos/domain/sesion_clase.dart';
import '../../evaluaciones/data/evaluaciones_repository.dart';
import '../../evaluaciones/domain/evaluacion.dart';

final cursosRepoProvider = Provider<CursosRepository>(
  (ref) => CursosRepository(ref.watch(matixClientProvider)),
);

final evaluacionesRepoProvider = Provider<EvaluacionesRepository>((ref) {
  return EvaluacionesRepository(
    ref.watch(matixClientProvider),
    ref.watch(notificacionesServiceProvider),
  );
});

final cursosListProvider = FutureProvider<List<Curso>>(
  (ref) => ref.watch(cursosRepoProvider).listar(),
);

final sesionesClaseProvider = FutureProvider<List<SesionClase>>(
  (ref) => ref.watch(cursosRepoProvider).listarSesiones(),
);

/// Sesiones que ocurren el día `d`, ya enriquecidas con el curso.
final sesionesDelDiaProvider =
    Provider.family<List<(SesionClase, Curso?)>, DateTime>((ref, d) {
  final ses = ref.watch(sesionesClaseProvider).valueOrNull ?? const [];
  final cursos = ref.watch(cursosListProvider).valueOrNull ?? const <Curso>[];
  final cursosMap = {for (final c in cursos) c.id: c};
  final del = ses.where((s) => s.ocurreEn(d)).toList()
    ..sort((a, b) => a.horaInicio.compareTo(b.horaInicio));
  return [for (final s in del) (s, cursosMap[s.cursoId])];
});

/// Sesiones de un curso concreto, ordenadas por día y hora.
final sesionesDeCursoProvider =
    Provider.family<List<SesionClase>, String>((ref, cursoId) {
  final ses = ref.watch(sesionesClaseProvider).valueOrNull ?? const [];
  final lista = ses.where((s) => s.cursoId == cursoId).toList()
    ..sort((a, b) {
      final d = a.diaSemana.compareTo(b.diaSemana);
      return d != 0 ? d : a.horaInicio.compareTo(b.horaInicio);
    });
  return lista;
});

final evaluacionesListProvider = FutureProvider<List<Evaluacion>>(
  (ref) => ref.watch(evaluacionesRepoProvider).listar(),
);

/// Evaluaciones de un curso concreto.
final evaluacionesDeCursoProvider =
    Provider.family<AsyncValue<List<Evaluacion>>, String>((ref, cursoId) {
  return ref.watch(evaluacionesListProvider).whenData((todas) {
    final lista = todas.where((e) => e.cursoId == cursoId).toList()
      ..sort((a, b) => a.fecha.compareTo(b.fecha));
    return lista;
  });
});

/// Promedio ponderado de un curso (sobre 20 por defecto del cerebro).
double? promedioCurso(List<Evaluacion> evs) {
  final cal = evs.where((e) => e.tieneNota).toList();
  if (cal.isEmpty) return null;
  // Si hay pesos, promedio ponderado; si no, simple.
  final tienenPeso = cal.every((e) => e.peso != null);
  if (tienenPeso) {
    final sumaPeso = cal.fold<double>(0, (acc, e) => acc + (e.peso ?? 0));
    if (sumaPeso == 0) return null;
    final sum = cal.fold<double>(
        0,
        (acc, e) =>
            acc + ((e.notaObtenida ?? 0) * (e.peso ?? 0) / sumaPeso));
    return sum;
  }
  final suma = cal.fold<double>(0, (acc, e) => acc + (e.notaObtenida ?? 0));
  return suma / cal.length;
}
