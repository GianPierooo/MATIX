import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tareas/providers/tareas_providers.dart';
import '../data/nudges_prefs.dart';
import '../domain/nudges.dart';

final nudgesPrefsProvider = Provider<NudgesPrefs>((_) => NudgesPrefs());

/// Estado de la config global de nudges (intensidad + horas de
/// silencio). Lee de SharedPreferences al arrancar y persiste cada
/// cambio. Al cambiar algo global, reprograma los nudges de TODAS las
/// tareas para que la nueva intensidad/silencio aplique de inmediato.
class NudgesConfigController extends StateNotifier<NudgesConfig> {
  NudgesConfigController(this._prefs, this._ref)
      : super(const NudgesConfig()) {
    _ready = _cargar();
  }

  final NudgesPrefs _prefs;
  final Ref _ref;
  late final Future<void> _ready;

  Future<void> get ready => _ready;

  Future<void> _cargar() async {
    state = await _prefs.leerConfig();
  }

  Future<void> cambiarIntensidad(IntensidadNudge v) async {
    await _ready;
    state = state.copyWith(intensidad: v);
    await _prefs.guardarConfig(state);
    await _reprogramarTodas();
  }

  Future<void> cambiarSilencio(int inicio, int fin) async {
    await _ready;
    state = state.copyWith(silencio: HorasSilencio(inicio: inicio, fin: fin));
    await _prefs.guardarConfig(state);
    await _reprogramarTodas();
  }

  Future<void> _reprogramarTodas() async {
    // Best-effort: si no hay red al releer las tareas, no rompemos el
    // cambio de ajuste — el próximo edit de cada tarea la reprograma.
    try {
      await _ref.read(tareasRepositoryProvider).reprogramarNudgesDeTodas();
    } catch (_) {}
  }
}

final nudgesConfigProvider =
    StateNotifierProvider<NudgesConfigController, NudgesConfig>((ref) {
  return NudgesConfigController(ref.watch(nudgesPrefsProvider), ref);
});
