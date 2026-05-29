import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../eventos/domain/evento.dart';
import '../../eventos/providers/eventos_providers.dart';
import '../../nudges/domain/nudges.dart';
import '../../nudges/providers/nudges_providers.dart';
import '../../tareas/domain/tarea.dart';
import '../../tareas/providers/tareas_providers.dart';
import '../data/duraciones_repository.dart';
import '../data/planificador_prefs.dart';
import '../domain/planificador.dart';

final planificadorPrefsProvider = Provider((_) => PlanificadorPrefs());

final duracionesRepositoryProvider = Provider<DuracionesRepository>(
  (ref) => DuracionesRepository(ref.watch(matixClientProvider)),
);

/// Fases del flujo "planifica mi día":
/// `inicial` → `planificando` (Matix estima y se arma la propuesta) →
/// `revision` (ajustas/quitas) → `aplicando` → `aplicado` / `error`.
enum FasePlan { inicial, planificando, revision, aplicando, aplicado, error }

@immutable
class EstadoPlan {
  const EstadoPlan({
    this.fase = FasePlan.inicial,
    this.plan,
    this.error,
    this.aplicados = 0,
  });

  final FasePlan fase;
  final ResultadoPlan? plan;
  final String? error;
  final int aplicados;

  EstadoPlan copyWith({
    FasePlan? fase,
    ResultadoPlan? plan,
    Object? error = _sentinel,
    int? aplicados,
  }) {
    return EstadoPlan(
      fase: fase ?? this.fase,
      plan: plan ?? this.plan,
      error: identical(error, _sentinel) ? this.error : error as String?,
      aplicados: aplicados ?? this.aplicados,
    );
  }

  static const _sentinel = Object();
}

/// Orquesta planificar → revisar → aplicar. La propuesta es
/// determinística (la arma `planificarDia`); Matix solo aporta la
/// duración estimada de cada tarea. Las ediciones de la revisión
/// (ajustar duración, quitar) recalculan el plan. Al aplicar, cada
/// bloque aceptado se guarda en su tarea (bloque_inicio/fin), que
/// alimenta los contadores y nudges de Urgencia-1/2.
class PlanDiaController extends Notifier<EstadoPlan> {
  List<Tarea> _tareas = const [];
  List<Evento> _eventos = const [];
  VentanaTrabajo _ventana = const VentanaTrabajo();
  HorasSilencio _silencio = const HorasSilencio();
  final Map<String, int> _duraciones = {};
  final Set<String> _excluidas = {};
  DateTime _ahora = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  EstadoPlan build() => const EstadoPlan();

  /// [ahora] solo se inyecta en tests para que el encaje sea
  /// determinístico; en la app real se usa el reloj.
  Future<void> planificar({DateTime? ahora}) async {
    state = const EstadoPlan(fase: FasePlan.planificando);
    try {
      _ahora = ahora ?? DateTime.now();
      final dia = DateTime(_ahora.year, _ahora.month, _ahora.day);
      final todas = await ref.read(tareasProvider.future);
      _tareas = todas.where((t) => !t.completada).toList();
      // Aseguramos cargados los eventos base y leemos los de hoy
      // (con recurrencias expandidas) del provider derivado.
      await ref.read(eventosProvider.future);
      _eventos =
          ref.read(eventosDelDiaProvider(dia)).valueOrNull ?? const <Evento>[];
      _ventana = await ref.read(planificadorPrefsProvider).leerVentana();
      _silencio = (await ref.read(nudgesPrefsProvider).leerConfig()).silencio;
      _excluidas.clear();
      _duraciones.clear();
      // Matix estima las duraciones. Si falla (sin red, sin API key),
      // seguimos con el default — el plan nunca se queda mudo.
      try {
        _duraciones.addAll(
          await ref.read(duracionesRepositoryProvider).estimar(_tareas),
        );
      } catch (_) {}
      _repack();
    } catch (e) {
      state = EstadoPlan(
        fase: FasePlan.error,
        error: 'No pude armar el plan: $e',
      );
    }
  }

  void _repack() {
    final tareas =
        _tareas.where((t) => !_excluidas.contains(t.id)).toList();
    final plan = planificarDia(
      tareas: tareas,
      eventos: _eventos,
      ahora: _ahora,
      ventana: _ventana,
      silencio: _silencio,
      duracionesMin: _duraciones,
    );
    state = EstadoPlan(fase: FasePlan.revision, plan: plan);
  }

  /// Ajusta la duración de un bloque (en minutos) y recalcula el día.
  void ajustarDuracion(String tareaId, int minutos) {
    _duraciones[tareaId] = minutos.clamp(15, 600);
    _repack();
  }

  /// Quita una tarea del plan; el día se recalcula sin ella.
  void quitar(String tareaId) {
    _excluidas.add(tareaId);
    _repack();
  }

  /// Aplica los bloques aceptados: cada tarea queda con su bloque
  /// (inicio/fin). Eso dispara contadores y nudges. Si una falla,
  /// vuelve a revisión con el error (las ya aplicadas quedan).
  Future<void> aplicar() async {
    final plan = state.plan;
    if (plan == null || plan.bloques.isEmpty) return;
    state = state.copyWith(fase: FasePlan.aplicando, error: null);
    final repo = ref.read(tareasRepositoryProvider);
    var n = 0;
    try {
      for (final b in plan.bloques) {
        await repo.actualizar(b.tareaId, {
          'bloque_inicio': b.inicio.toUtc().toIso8601String(),
          'bloque_fin': b.fin.toUtc().toIso8601String(),
        });
        n++;
      }
      ref.invalidate(tareasProvider);
      state = state.copyWith(fase: FasePlan.aplicado, aplicados: n);
    } catch (e) {
      if (n > 0) ref.invalidate(tareasProvider);
      state = state.copyWith(
        fase: FasePlan.revision,
        error: n == 0
            ? 'No pude aplicar el plan: $e'
            : 'Apliqué $n y luego falló: $e. Reintenta.',
      );
    }
  }

  void reiniciar() {
    _excluidas.clear();
    _duraciones.clear();
    state = const EstadoPlan();
  }
}

final planDiaControllerProvider =
    NotifierProvider<PlanDiaController, EstadoPlan>(PlanDiaController.new);

/// Estado de la ventana de trabajo (ajuste global, Urgencia-3). Lee de
/// prefs al arrancar y persiste cada cambio.
class VentanaController extends StateNotifier<VentanaTrabajo> {
  VentanaController(this._prefs) : super(const VentanaTrabajo()) {
    _ready = _cargar();
  }
  final PlanificadorPrefs _prefs;
  late final Future<void> _ready;
  Future<void> get ready => _ready;

  Future<void> _cargar() async {
    state = await _prefs.leerVentana();
  }

  Future<void> cambiar(int inicio, int fin) async {
    await _ready;
    state = VentanaTrabajo(inicio: inicio, fin: fin);
    await _prefs.guardarVentana(state);
  }
}

final ventanaTrabajoProvider =
    StateNotifierProvider<VentanaController, VentanaTrabajo>((ref) {
  return VentanaController(ref.watch(planificadorPrefsProvider));
});
