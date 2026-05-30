import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../../core/providers.dart';
import '../../eventos/providers/eventos_providers.dart';
import '../data/extraccion_eventos_repository.dart';
import '../domain/evento_propuesto.dart';

/// Fases del flujo sílabo → eventos (Cámara · sílabo): mismo patrón que
/// las tareas (7-B).
enum FaseEventos { inicial, interpretando, revision, creando, creado, error }

@immutable
class EstadoEventos {
  const EstadoEventos({
    this.fase = FaseEventos.inicial,
    this.propuestas = const [],
    this.error,
    this.creados = 0,
  });

  final FaseEventos fase;
  final List<EventoPropuesto> propuestas;
  final String? error;
  final int creados;

  /// El cerebro respondió pero no encontró nada datable.
  bool get sinEventos =>
      fase == FaseEventos.revision && propuestas.isEmpty;

  EstadoEventos copyWith({
    FaseEventos? fase,
    List<EventoPropuesto>? propuestas,
    Object? error = _kSentinel,
    int? creados,
  }) {
    return EstadoEventos(
      fase: fase ?? this.fase,
      propuestas: propuestas ?? this.propuestas,
      error: identical(error, _kSentinel) ? this.error : error as String?,
      creados: creados ?? this.creados,
    );
  }

  static const _kSentinel = Object();
}

/// Orquesta interpretar → revisar → crear (sílabo → eventos). Mismo
/// esqueleto que `ExtraccionTareasController`: el texto se interpreta
/// una vez; las ediciones mutan el estado local; al confirmar se crean
/// los eventos con el calendario de siempre (recurrentes con la
/// recurrencia de Cal-3, únicos como eventos normales) y se invalida
/// `eventosProvider`.
class ExtraccionEventosController extends Notifier<EstadoEventos> {
  @override
  EstadoEventos build() => const EstadoEventos();

  Future<void> interpretar(String texto) async {
    final limpio = texto.trim();
    if (limpio.isEmpty) {
      state = const EstadoEventos(
        fase: FaseEventos.error,
        error: 'No hay texto que convertir. Escribe o captura algo primero.',
      );
      return;
    }
    state = const EstadoEventos(fase: FaseEventos.interpretando);
    try {
      final propuestas = await ref
          .read(extraccionEventosRepositoryProvider)
          .extraer(limpio);
      state = EstadoEventos(
        fase: FaseEventos.revision,
        propuestas: propuestas,
      );
    } on MatixApiException catch (e) {
      state = EstadoEventos(
        fase: FaseEventos.error,
        error: 'No pude leer el sílabo: ${e.message}',
      );
    } catch (e) {
      state = EstadoEventos(
        fase: FaseEventos.error,
        error: 'No pude leer el sílabo: $e',
      );
    }
  }

  // ─── Ediciones de la hoja de revisión ────────────────────────────────

  void editarTitulo(int i, String titulo) =>
      _editar(i, (p) => p.copyWith(titulo: titulo));

  void ponerFecha(int i, DateTime fecha) =>
      _editar(i, (p) => p.copyWith(fecha: fecha));

  void ponerHoraInicio(int i, String? hora) =>
      _editar(i, (p) => p.copyWith(horaInicio: hora));

  void ponerHoraFin(int i, String? hora) =>
      _editar(i, (p) => p.copyWith(horaFin: hora));

  void alternarDia(int i, int dia) {
    _editar(i, (p) {
      final dias = {...p.diasSemana};
      if (!dias.remove(dia)) dias.add(dia);
      return p.copyWith(diasSemana: dias);
    });
  }

  void asignarCurso(int i, String? cursoId, String? color) =>
      _editar(i, (p) => p.copyWith(cursoId: cursoId, color: color));

  void eliminar(int i) {
    if (i < 0 || i >= state.propuestas.length) return;
    final nuevas = [...state.propuestas]..removeAt(i);
    state = state.copyWith(propuestas: nuevas);
  }

  void _editar(int i, EventoPropuesto Function(EventoPropuesto) f) {
    if (i < 0 || i >= state.propuestas.length) return;
    final nuevas = [...state.propuestas];
    nuevas[i] = f(nuevas[i]);
    state = state.copyWith(propuestas: nuevas);
  }

  // ─── Confirmación ────────────────────────────────────────────────────

  Future<void> crear() async {
    final propuestas = state.propuestas;
    if (propuestas.isEmpty || state.fase == FaseEventos.creando) return;
    state = state.copyWith(fase: FaseEventos.creando, error: null);
    final repo = ref.read(eventosRepositoryProvider);
    final ahora = DateTime.now();
    var creados = 0;
    try {
      for (final p in propuestas) {
        final titulo = p.titulo.trim();
        if (titulo.isEmpty) continue;
        final par = parametrosDe(p, ahora);
        await repo.crear(
          titulo: titulo,
          iniciaEn: par.iniciaEn,
          terminaEn: par.terminaEn,
          todoElDia: par.todoElDia,
          regla: par.regla,
          cursoId: p.cursoId,
          color: p.color,
        );
        creados++;
      }
      ref.invalidate(eventosProvider);
      state = state.copyWith(fase: FaseEventos.creado, creados: creados);
    } on MatixApiException catch (e) {
      if (creados > 0) ref.invalidate(eventosProvider);
      state = state.copyWith(
        fase: FaseEventos.revision,
        error: creados == 0
            ? 'No pude crear los eventos: ${e.message}'
            : 'Creé $creados y luego falló: ${e.message}. Reintenta.',
      );
    } catch (e) {
      if (creados > 0) ref.invalidate(eventosProvider);
      state = state.copyWith(
        fase: FaseEventos.revision,
        error: 'No pude crear los eventos: $e. Reintenta.',
      );
    }
  }

  void reiniciar() => state = const EstadoEventos();
}

final extraccionEventosRepositoryProvider =
    Provider<ExtraccionEventosRepository>((ref) {
  return ExtraccionEventosRepository(ref.watch(matixClientProvider));
});

final extraccionEventosControllerProvider =
    NotifierProvider<ExtraccionEventosController, EstadoEventos>(
        ExtraccionEventosController.new);
