import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../../core/providers.dart';
import '../../tareas/providers/tareas_providers.dart';
import '../data/extraccion_tareas_repository.dart';
import '../domain/tarea_propuesta.dart';

/// Fases del flujo texto → tareas (Capa 7-B):
///
/// `inicial`: aún no se mandó nada al cerebro.
/// `interpretando`: el cerebro está extrayendo las tareas del texto.
/// `revision`: llegaron las propuestas; el usuario las edita/confirma.
/// `creando`: confirmó — estamos creando con el CRUD una por una.
/// `creado`: se crearon `creadas` tareas; fin del flujo.
/// `error`: falló la interpretación; `error` trae el mensaje + reintento.
enum FaseExtraccion { inicial, interpretando, revision, creando, creado, error }

@immutable
class EstadoExtraccion {
  const EstadoExtraccion({
    this.fase = FaseExtraccion.inicial,
    this.propuestas = const [],
    this.error,
    this.creadas = 0,
  });

  final FaseExtraccion fase;
  final List<TareaPropuesta> propuestas;

  /// Mensaje de error visible. En `error` es un fallo de
  /// interpretación; en `revision` puede traer un fallo al crear
  /// (mostramos banner + permitimos reintentar la creación).
  final String? error;

  /// Cuántas tareas se crearon al confirmar (para el mensaje final).
  final int creadas;

  /// El cerebro respondió pero no encontró tareas claras.
  bool get sinTareas =>
      fase == FaseExtraccion.revision && propuestas.isEmpty;

  EstadoExtraccion copyWith({
    FaseExtraccion? fase,
    List<TareaPropuesta>? propuestas,
    Object? error = _kSentinel,
    int? creadas,
  }) {
    return EstadoExtraccion(
      fase: fase ?? this.fase,
      propuestas: propuestas ?? this.propuestas,
      error: identical(error, _kSentinel) ? this.error : error as String?,
      creadas: creadas ?? this.creadas,
    );
  }

  static const _kSentinel = Object();
}

/// Orquesta interpretar → revisar → crear. El texto se interpreta una
/// vez; las ediciones de la hoja de revisión mutan el estado local
/// (sin volver a llamar al cerebro); al confirmar se crean las tareas
/// con el `TareasRepository` de siempre y se invalida la lista para
/// que aparezcan al instante en Tareas y en el "Hoy" de Inicio.
class ExtraccionTareasController extends Notifier<EstadoExtraccion> {
  @override
  EstadoExtraccion build() => const EstadoExtraccion();

  /// Manda el texto corregido al cerebro. Deja el estado en `revision`
  /// (con o sin propuestas) si todo va bien, o en `error` con mensaje.
  Future<void> interpretar(String texto) async {
    final limpio = texto.trim();
    if (limpio.isEmpty) {
      state = const EstadoExtraccion(
        fase: FaseExtraccion.error,
        error: 'No hay texto que convertir. Escribe o captura algo primero.',
      );
      return;
    }
    state = const EstadoExtraccion(fase: FaseExtraccion.interpretando);
    try {
      final propuestas =
          await ref.read(extraccionTareasRepositoryProvider).extraer(limpio);
      state = EstadoExtraccion(
        fase: FaseExtraccion.revision,
        propuestas: propuestas,
      );
    } on MatixApiException catch (e) {
      state = EstadoExtraccion(
        fase: FaseExtraccion.error,
        error: 'No pude convertir el texto en tareas: ${e.message}',
      );
    } catch (e) {
      state = EstadoExtraccion(
        fase: FaseExtraccion.error,
        error: 'No pude convertir el texto en tareas: $e',
      );
    }
  }

  // ─── Ediciones de la hoja de revisión ────────────────────────────────

  void editarTitulo(int indice, String titulo) =>
      _editar(indice, (p) => p.copyWith(titulo: titulo));

  void ponerFecha(int indice, DateTime fecha) =>
      _editar(indice, (p) => p.copyWith(venceEn: fecha));

  void quitarFecha(int indice) =>
      _editar(indice, (p) => p.copyWith(venceEn: null));

  void asignarProyecto(int indice, String? proyectoId) =>
      _editar(indice, (p) => p.copyWith(proyectoId: proyectoId));

  void eliminar(int indice) {
    if (indice < 0 || indice >= state.propuestas.length) return;
    final nuevas = [...state.propuestas]..removeAt(indice);
    state = state.copyWith(propuestas: nuevas);
  }

  void _editar(int indice, TareaPropuesta Function(TareaPropuesta) f) {
    if (indice < 0 || indice >= state.propuestas.length) return;
    final nuevas = [...state.propuestas];
    nuevas[indice] = f(nuevas[indice]);
    state = state.copyWith(propuestas: nuevas);
  }

  // ─── Confirmación ────────────────────────────────────────────────────

  /// Crea TODAS las propuestas con el CRUD de tareas. Si una falla,
  /// detenemos y volvemos a `revision` con el error visible (las ya
  /// creadas quedan creadas; el usuario reintenta el resto). Al
  /// terminar bien, invalida `tareasProvider` para refrescar Tareas e
  /// Inicio.
  Future<void> crear() async {
    final propuestas = state.propuestas;
    if (propuestas.isEmpty || state.fase == FaseExtraccion.creando) return;

    state = state.copyWith(fase: FaseExtraccion.creando, error: null);
    final repo = ref.read(tareasRepositoryProvider);
    var creadas = 0;
    try {
      for (final p in propuestas) {
        final titulo = p.titulo.trim();
        if (titulo.isEmpty) continue;
        await repo.crear(
          titulo: titulo,
          venceEn: p.venceEn,
          proyectoId: p.proyectoId,
        );
        creadas++;
      }
      ref.invalidate(tareasProvider);
      state = state.copyWith(fase: FaseExtraccion.creado, creadas: creadas);
    } on MatixApiException catch (e) {
      if (creadas > 0) ref.invalidate(tareasProvider);
      state = state.copyWith(
        fase: FaseExtraccion.revision,
        error: creadas == 0
            ? 'No pude crear las tareas: ${e.message}'
            : 'Creé $creadas y luego falló: ${e.message}. Reintenta.',
      );
    } catch (e) {
      if (creadas > 0) ref.invalidate(tareasProvider);
      state = state.copyWith(
        fase: FaseExtraccion.revision,
        error: 'No pude crear las tareas: $e. Reintenta.',
      );
    }
  }

  void reiniciar() => state = const EstadoExtraccion();
}

final extraccionTareasRepositoryProvider =
    Provider<ExtraccionTareasRepository>((ref) {
  return ExtraccionTareasRepository(ref.watch(matixClientProvider));
});

final extraccionTareasControllerProvider =
    NotifierProvider<ExtraccionTareasController, EstadoExtraccion>(
        ExtraccionTareasController.new);
