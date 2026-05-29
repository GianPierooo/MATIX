import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../../core/providers.dart';
import '../../tareas/providers/tareas_providers.dart';
import '../data/desglose_repository.dart';
import '../domain/paso_propuesto.dart';

final desgloseRepositoryProvider = Provider<DesgloseRepository>(
  (ref) => DesgloseRepository(ref.watch(matixClientProvider)),
);

/// Fases del desglose:
/// `inicial` → `desglosando` (Matix propone) → `revision` (editas/quitas/
/// reordenas) → `creando` → `creado` / `error`. En `revision` con
/// `esAtomica=true` no hay pasos: la tarea ya era accionable.
enum FaseDesglose { inicial, desglosando, revision, creando, creado, error }

@immutable
class EstadoDesglose {
  const EstadoDesglose({
    this.fase = FaseDesglose.inicial,
    this.pasos = const [],
    this.esAtomica = false,
    this.error,
    this.creados = 0,
  });

  final FaseDesglose fase;
  final List<PasoPropuesto> pasos;
  final bool esAtomica;
  final String? error;
  final int creados;

  EstadoDesglose copyWith({
    FaseDesglose? fase,
    List<PasoPropuesto>? pasos,
    bool? esAtomica,
    Object? error = _sentinel,
    int? creados,
  }) {
    return EstadoDesglose(
      fase: fase ?? this.fase,
      pasos: pasos ?? this.pasos,
      esAtomica: esAtomica ?? this.esAtomica,
      error: identical(error, _sentinel) ? this.error : error as String?,
      creados: creados ?? this.creados,
    );
  }

  static const _sentinel = Object();
}

/// Orquesta desglosar → revisar → crear. El desglose lo propone Matix
/// (cerebro/OpenAI); las ediciones de la revisión mutan el estado local
/// (sin volver a llamar al modelo); al confirmar se crean los pasos como
/// tareas en el MISMO proyecto/curso de la tarea origen.
class DesgloseController extends Notifier<EstadoDesglose> {
  // Contexto heredado de la tarea origen (no se vuelve a pedir).
  String? _proyectoId;
  String? _cursoId;

  @override
  EstadoDesglose build() => const EstadoDesglose();

  Future<void> desglosar({
    required String titulo,
    String? nota,
    String? proyectoId,
    String? cursoId,
  }) async {
    _proyectoId = proyectoId;
    _cursoId = cursoId;
    state = const EstadoDesglose(fase: FaseDesglose.desglosando);
    try {
      final r =
          await ref.read(desgloseRepositoryProvider).desglosar(
                titulo: titulo,
                nota: nota,
              );
      state = EstadoDesglose(
        fase: FaseDesglose.revision,
        pasos: r.pasos,
        esAtomica: r.esAtomica,
      );
    } on MatixApiException catch (e) {
      state = EstadoDesglose(
        fase: FaseDesglose.error,
        error: 'No pude desglosar la tarea: ${e.message}',
      );
    } catch (e) {
      state = EstadoDesglose(
        fase: FaseDesglose.error,
        error: 'No pude desglosar la tarea: $e',
      );
    }
  }

  void editarTitulo(int indice, String titulo) =>
      _editar(indice, (p) => p.copyWith(titulo: titulo));

  void cambiarHorizonte(int indice, Horizonte h) =>
      _editar(indice, (p) => p.copyWith(horizonte: h));

  void quitar(int indice) {
    if (indice < 0 || indice >= state.pasos.length) return;
    final nuevas = [...state.pasos]..removeAt(indice);
    state = state.copyWith(pasos: nuevas);
  }

  /// Reordena (semántica de `ReorderableListView`).
  void reordenar(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final nuevas = [...state.pasos];
    final p = nuevas.removeAt(oldIndex);
    nuevas.insert(newIndex, p);
    state = state.copyWith(pasos: nuevas);
  }

  void _editar(int indice, PasoPropuesto Function(PasoPropuesto) f) {
    if (indice < 0 || indice >= state.pasos.length) return;
    final nuevas = [...state.pasos];
    nuevas[indice] = f(nuevas[indice]);
    state = state.copyWith(pasos: nuevas);
  }

  /// Crea los pasos como tareas en el proyecto/curso de la original.
  /// El horizonte viaja como prioridad (ahora→alta, etc.). Si una falla,
  /// vuelve a revisión con el error; las ya creadas quedan creadas.
  Future<void> crear() async {
    final pasos = state.pasos;
    if (pasos.isEmpty || state.fase == FaseDesglose.creando) return;
    state = state.copyWith(fase: FaseDesglose.creando, error: null);
    final repo = ref.read(tareasRepositoryProvider);
    var creados = 0;
    try {
      for (final p in pasos) {
        final titulo = p.titulo.trim();
        if (titulo.isEmpty) continue;
        await repo.crear(
          titulo: titulo,
          prioridad: p.horizonte.prioridad,
          proyectoId: _proyectoId,
          cursoId: _cursoId,
        );
        creados++;
      }
      ref.invalidate(tareasProvider);
      state = state.copyWith(fase: FaseDesglose.creado, creados: creados);
    } on MatixApiException catch (e) {
      if (creados > 0) ref.invalidate(tareasProvider);
      state = state.copyWith(
        fase: FaseDesglose.revision,
        error: creados == 0
            ? 'No pude crear los pasos: ${e.message}'
            : 'Creé $creados y luego falló: ${e.message}. Reintenta.',
      );
    } catch (e) {
      if (creados > 0) ref.invalidate(tareasProvider);
      state = state.copyWith(
        fase: FaseDesglose.revision,
        error: 'No pude crear los pasos: $e. Reintenta.',
      );
    }
  }

  void reiniciar() {
    _proyectoId = null;
    _cursoId = null;
    state = const EstadoDesglose();
  }
}

final desgloseControllerProvider =
    NotifierProvider<DesgloseController, EstadoDesglose>(
        DesgloseController.new);
