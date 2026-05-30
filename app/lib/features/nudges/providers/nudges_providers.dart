import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/nudges_prefs.dart';
import '../data/nudges_repository.dart';

/// `nudgesPrefsProvider` sigue vivo: lo usa el planificador del día
/// ("Planifica mi día") para leer las horas de silencio locales. Los
/// nudges en sí ya no se programan localmente — los manda el cerebro.
final nudgesPrefsProvider = Provider<NudgesPrefs>((_) => NudgesPrefs());

/// Estado de la config de nudges para la UI de Ajustes (Push Capa 3b):
/// maestro on/off + horas de silencio. Vive en el CEREBRO (el scheduler
/// la respeta), así que la cargamos y persistimos contra el servidor.
/// Intenso por defecto: ya no hay selector Suave/Normal/Fuerte.
class NudgesUiConfig {
  const NudgesUiConfig({
    this.activo = true,
    this.silencioInicio = 22,
    this.silencioFin = 8,
  });

  final bool activo;
  final int silencioInicio;
  final int silencioFin;

  NudgesUiConfig copyWith({bool? activo, int? silencioInicio, int? silencioFin}) =>
      NudgesUiConfig(
        activo: activo ?? this.activo,
        silencioInicio: silencioInicio ?? this.silencioInicio,
        silencioFin: silencioFin ?? this.silencioFin,
      );
}

class NudgesConfigController extends StateNotifier<NudgesUiConfig> {
  NudgesConfigController(this._repo) : super(const NudgesUiConfig()) {
    _ready = _cargar();
  }

  final NudgesRepository _repo;
  late final Future<void> _ready;
  Future<void> get ready => _ready;

  Future<void> _cargar() async {
    try {
      final c = await _repo.obtener();
      if (c != null) {
        state = NudgesUiConfig(
          activo: c.activo,
          silencioInicio: c.silencioInicio,
          silencioFin: c.silencioFin,
        );
      }
    } catch (_) {
      // Sin red / migración sin aplicar: dejamos el default (ON, 22–08).
    }
  }

  Future<void> cambiarActivo(bool v) async {
    state = state.copyWith(activo: v);
    try {
      await _repo.actualizar(activo: v);
    } catch (_) {}
  }

  Future<void> cambiarSilencio(int inicio, int fin) async {
    state = state.copyWith(silencioInicio: inicio, silencioFin: fin);
    try {
      await _repo.actualizar(silencioInicio: inicio, silencioFin: fin);
    } catch (_) {}
  }
}

final nudgesConfigProvider =
    StateNotifierProvider<NudgesConfigController, NudgesUiConfig>((ref) {
  return NudgesConfigController(ref.watch(nudgesRepositoryProvider));
});
