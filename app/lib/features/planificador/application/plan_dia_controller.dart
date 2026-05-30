import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../eventos/domain/evento.dart';
import '../../eventos/providers/eventos_providers.dart';
import '../../nudges/data/nudges_repository.dart';
import '../../nudges/domain/nudges.dart';
import '../../tareas/domain/tarea.dart';
import '../../tareas/providers/tareas_providers.dart';
import '../data/duraciones_repository.dart';
import '../data/planificador_prefs.dart';
import '../domain/disponibilidad.dart';
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
  DisponibilidadSemanal _disponibilidad = DisponibilidadSemanal.porDefecto;
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
      _disponibilidad =
          await ref.read(planificadorPrefsProvider).leerDisponibilidad();
      // Las horas de silencio ahora viven en el CEREBRO (Push Capa 3b):
      // el planificador no debe encajar bloques de trabajo dentro de
      // ellas, así que las leemos del servidor. Si falla la red, caemos
      // al default local (22–08), nunca dejamos el plan mudo.
      _silencio = await _leerSilencio();
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

  /// Lee las horas de silencio del cerebro (fuente de verdad desde Push
  /// Capa 3b). Si no hay red / config, usa el default local.
  Future<HorasSilencio> _leerSilencio() async {
    try {
      final cfg = await ref.read(nudgesRepositoryProvider).obtener();
      if (cfg != null) {
        return HorasSilencio(inicio: cfg.silencioInicio, fin: cfg.silencioFin);
      }
    } catch (_) {}
    return const HorasSilencio();
  }

  void _repack() {
    final tareas =
        _tareas.where((t) => !_excluidas.contains(t.id)).toList();
    final plan = planificarDia(
      tareas: tareas,
      eventos: _eventos,
      ahora: _ahora,
      disponibilidad: _disponibilidad,
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

/// Estado de la disponibilidad por día (Fase 3). Lee de prefs al
/// arrancar y persiste cada cambio. Lo consume el ajuste de
/// disponibilidad y, hoy, el planificador del día (Urgencia-3); mañana,
/// el planificador de sesiones (Fase 4).
class DisponibilidadController extends StateNotifier<DisponibilidadSemanal> {
  DisponibilidadController(this._prefs, this._nudgesRepo)
      : super(DisponibilidadSemanal.porDefecto) {
    _ready = _cargar();
  }
  final PlanificadorPrefs _prefs;
  final NudgesRepository _nudgesRepo;
  late final Future<void> _ready;
  Future<void> get ready => _ready;

  Future<void> _cargar() async {
    state = await _prefs.leerDisponibilidad();
  }

  /// Cambia la disponibilidad de un día ISO (1=lun … 7=dom) y persiste.
  /// La disponibilidad también la respeta el scheduler de nudges del
  /// CEREBRO (Push Capa 3b): solo te empuja dentro de tus ventanas. Por
  /// eso, además de guardarla local (la usa el planificador del día), la
  /// sincronizamos al servidor en cada cambio. Best-effort: si la red
  /// falla, el cambio local queda igual.
  Future<void> cambiarDia(int weekday, DisponibilidadDia dia) async {
    await _ready;
    state = state.conDia(weekday, dia);
    await _prefs.guardarDisponibilidad(state);
    try {
      await _nudgesRepo.actualizar(disponibilidad: _aServidor(state));
    } catch (_) {}
  }

  /// Mapa por día ISO en string ("1".."7") → {activo, inicio, fin}, el
  /// formato que espera el cerebro.
  static Map<String, dynamic> _aServidor(DisponibilidadSemanal d) => {
        for (var w = 1; w <= 7; w++)
          '$w': {
            'activo': d.diaDe(w).activo,
            'inicio': d.diaDe(w).inicio,
            'fin': d.diaDe(w).fin,
          },
      };
}

final disponibilidadProvider =
    StateNotifierProvider<DisponibilidadController, DisponibilidadSemanal>(
        (ref) {
  return DisponibilidadController(
    ref.watch(planificadorPrefsProvider),
    ref.watch(nudgesRepositoryProvider),
  );
});
