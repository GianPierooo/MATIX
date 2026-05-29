import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notificaciones_service.dart';
import '../../../core/providers.dart';
import '../../nudges/providers/nudges_providers.dart';
import '../data/selectores_repository.dart';
import '../data/tareas_repository.dart';
import '../domain/selectores.dart';
import '../domain/tarea.dart';

// ───────────────────── Repositorios ───────────────────────────────────────

final tareasRepositoryProvider = Provider<TareasRepository>((ref) {
  return TareasRepository(
    ref.watch(matixClientProvider),
    ref.watch(notificacionesServiceProvider),
    ref.watch(nudgesPrefsProvider),
  );
});

final selectoresRepositoryProvider = Provider<SelectoresRepository>((ref) {
  return SelectoresRepository(ref.watch(matixClientProvider));
});

// ───────────────────── Datos remotos ──────────────────────────────────────

/// Lista cruda de tareas. El refresh manual se hace con `ref.invalidate`.
final tareasProvider = FutureProvider<List<Tarea>>((ref) async {
  final repo = ref.watch(tareasRepositoryProvider);
  return repo.listar();
});

/// Tarea por id — deriva de la lista para no hacer fetch extra.
final tareaPorIdProvider =
    Provider.family<Tarea?, String>((ref, id) {
  final lista = ref.watch(tareasProvider).valueOrNull ?? const <Tarea>[];
  for (final t in lista) {
    if (t.id == id) return t;
  }
  return null;
});

/// Tareas pertenecientes a un proyecto, ordenadas por vencimiento.
final tareasDeProyectoProvider =
    Provider.family<List<Tarea>, String>((ref, proyectoId) {
  final lista = ref.watch(tareasProvider).valueOrNull ?? const <Tarea>[];
  final out = lista.where((t) => t.proyectoId == proyectoId).toList()
    ..sort((a, b) {
      if (a.completada != b.completada) return a.completada ? 1 : -1;
      if (a.venceEn == null && b.venceEn == null) return 0;
      if (a.venceEn == null) return 1;
      if (b.venceEn == null) return -1;
      return a.venceEn!.compareTo(b.venceEn!);
    });
  return out;
});

/// Subtareas de UNA tarea concreta — se usa en NuevaTareaScreen.
/// El filtro se aplica en el cerebro (query `?tarea_id=`); la app
/// solo recibe las que necesita.
final subtareasDeProvider =
    FutureProvider.family<List<Subtarea>, String>((ref, tareaId) async {
  final repo = ref.watch(tareasRepositoryProvider);
  final lista = await repo.listarSubtareasDe(tareaId);
  // El cerebro ya las devuelve ordenadas por `orden` (Postgres lo hace
  // en el SELECT), pero garantizamos consistencia ante cambios futuros.
  final out = [...lista]..sort((a, b) => a.orden.compareTo(b.orden));
  return out;
});

final categoriasProvider = FutureProvider<List<CategoriaRef>>((ref) async {
  final lista = await ref.watch(selectoresRepositoryProvider).categorias();
  _publicarSnapshotIfReady(ref);
  return lista;
});

final cursosProvider = FutureProvider<List<CursoRef>>((ref) async {
  final lista = await ref.watch(selectoresRepositoryProvider).cursos();
  _publicarSnapshotIfReady(ref);
  return lista;
});

final proyectosProvider = FutureProvider<List<ProyectoRef>>((ref) async {
  final lista = await ref.watch(selectoresRepositoryProvider).proyectos();
  _publicarSnapshotIfReady(ref);
  return lista;
});

/// Cuando los 3 selectores están cargados, publicamos el snapshot al
/// `TareasRepository` para que los cuerpos de notificación tengan el
/// nombre del curso/proyecto/categoría sin tener que pasarles `ref`.
void _publicarSnapshotIfReady(Ref ref) {
  final c = ref.read(categoriasProvider).valueOrNull;
  final cu = ref.read(cursosProvider).valueOrNull;
  final p = ref.read(proyectosProvider).valueOrNull;
  if (c != null && cu != null && p != null) {
    TareasRepository.actualizarSelectoresCache(
      categorias: c, cursos: cu, proyectos: p,
    );
  }
}

// ───────────────────── Vista activa y filtros ─────────────────────────────

enum VistaTareas {
  hoy,
  semana,
  todas,
  completadas,
  porCurso;

  String get label => switch (this) {
        VistaTareas.hoy => 'Hoy',
        VistaTareas.semana => 'Esta semana',
        VistaTareas.todas => 'Todas',
        VistaTareas.completadas => 'Completadas',
        VistaTareas.porCurso => 'Por curso',
      };
}

final vistaTareasProvider =
    NotifierProvider<VistaTareasNotifier, VistaTareas>(VistaTareasNotifier.new);

class VistaTareasNotifier extends Notifier<VistaTareas> {
  @override
  VistaTareas build() => VistaTareas.hoy;

  void set(VistaTareas v) => state = v;
}

@immutable
class FiltrosTareas {
  const FiltrosTareas({
    this.categoriaId,
    this.cursoId,
    this.proyectoId,
    this.prioridad,
    this.venceEnDias,
  });

  /// `null` = sin filtro de esa dimensión.
  final String? categoriaId;
  final String? cursoId;
  final String? proyectoId;
  final Prioridad? prioridad;
  final int? venceEnDias; // ej. 3 = "que venzan en ≤3 días"

  bool get vacio =>
      categoriaId == null &&
      cursoId == null &&
      proyectoId == null &&
      prioridad == null &&
      venceEnDias == null;

  int get activos => [
        categoriaId,
        cursoId,
        proyectoId,
        prioridad,
        venceEnDias,
      ].where((e) => e != null).length;

  FiltrosTareas copyWith({
    Object? categoriaId = _kSentinel,
    Object? cursoId = _kSentinel,
    Object? proyectoId = _kSentinel,
    Object? prioridad = _kSentinel,
    Object? venceEnDias = _kSentinel,
  }) {
    return FiltrosTareas(
      categoriaId: identical(categoriaId, _kSentinel)
          ? this.categoriaId
          : categoriaId as String?,
      cursoId: identical(cursoId, _kSentinel) ? this.cursoId : cursoId as String?,
      proyectoId: identical(proyectoId, _kSentinel)
          ? this.proyectoId
          : proyectoId as String?,
      prioridad: identical(prioridad, _kSentinel)
          ? this.prioridad
          : prioridad as Prioridad?,
      venceEnDias: identical(venceEnDias, _kSentinel)
          ? this.venceEnDias
          : venceEnDias as int?,
    );
  }

  static const _kSentinel = Object();
}

final filtrosTareasProvider =
    NotifierProvider<FiltrosTareasNotifier, FiltrosTareas>(
        FiltrosTareasNotifier.new);

class FiltrosTareasNotifier extends Notifier<FiltrosTareas> {
  @override
  FiltrosTareas build() => const FiltrosTareas();

  void set(FiltrosTareas f) => state = f;
  void limpiar() => state = const FiltrosTareas();
}

// ───────────────────── Tareas filtradas (lo que la lista muestra) ────────

/// Aplica vista + filtros sobre la lista cruda, sin tocar la red.
final tareasFiltradasProvider = Provider<AsyncValue<List<Tarea>>>((ref) {
  final raw = ref.watch(tareasProvider);
  final vista = ref.watch(vistaTareasProvider);
  final f = ref.watch(filtrosTareasProvider);

  return raw.whenData((tareas) {
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final finSemana = hoy.add(const Duration(days: 7));

    Iterable<Tarea> out = tareas;

    // Vista
    switch (vista) {
      case VistaTareas.hoy:
        out = out.where((t) => !t.completada && t.venceHoy(ahora));
      case VistaTareas.semana:
        out = out.where((t) =>
            !t.completada &&
            t.venceEn != null &&
            t.venceEn!.isBefore(finSemana));
      case VistaTareas.todas:
        out = out.where((t) => !t.completada);
      case VistaTareas.completadas:
        out = out.where((t) => t.completada);
      case VistaTareas.porCurso:
        out = out.where((t) => !t.completada && t.cursoId != null);
    }

    // Filtros adicionales
    if (f.categoriaId != null) {
      out = out.where((t) => t.categoriaId == f.categoriaId);
    }
    if (f.cursoId != null) {
      out = out.where((t) => t.cursoId == f.cursoId);
    }
    if (f.proyectoId != null) {
      out = out.where((t) => t.proyectoId == f.proyectoId);
    }
    if (f.prioridad != null) {
      out = out.where((t) => t.prioridad == f.prioridad);
    }
    if (f.venceEnDias != null) {
      final limite = ahora.add(Duration(days: f.venceEnDias!));
      out = out.where((t) =>
          t.venceEn != null &&
          t.venceEn!.isBefore(limite));
    }

    // Orden: vencidas primero, luego por fecha de vencimiento, luego prioridad.
    final lista = out.toList()
      ..sort((a, b) {
        final av = a.estaVencida ? 0 : 1;
        final bv = b.estaVencida ? 0 : 1;
        if (av != bv) return av - bv;
        if (a.venceEn == null && b.venceEn == null) {
          return a.prioridad.index.compareTo(b.prioridad.index);
        }
        if (a.venceEn == null) return 1;
        if (b.venceEn == null) return -1;
        return a.venceEn!.compareTo(b.venceEn!);
      });
    return lista;
  });
});
