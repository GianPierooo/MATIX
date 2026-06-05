import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/proactividad_repository.dart';
import '../domain/nivel_proactividad.dart';

/// Estado del dial de proactividad para Ajustes: maestro on/off + nivel. Vive en
/// el CEREBRO (el scheduler lo respeta), así que se carga y persiste contra el
/// servidor. Arranca EXIGENTE por defecto, fácil de bajar si satura.
class ProactividadUiConfig {
  const ProactividadUiConfig({
    this.activo = true,
    this.nivel = NivelProactividad.exigente,
    this.leadLibreMin = 30,
  });

  final bool activo;
  final NivelProactividad nivel;
  final int leadLibreMin;

  ProactividadUiConfig copyWith({
    bool? activo,
    NivelProactividad? nivel,
    int? leadLibreMin,
  }) =>
      ProactividadUiConfig(
        activo: activo ?? this.activo,
        nivel: nivel ?? this.nivel,
        leadLibreMin: leadLibreMin ?? this.leadLibreMin,
      );
}

class ProactividadConfigController extends StateNotifier<ProactividadUiConfig> {
  ProactividadConfigController(this._repo)
      : super(const ProactividadUiConfig()) {
    _ready = _cargar();
  }

  final ProactividadRepository _repo;
  late final Future<void> _ready;
  Future<void> get ready => _ready;

  Future<void> _cargar() async {
    try {
      final c = await _repo.obtener();
      if (c != null) {
        state = ProactividadUiConfig(
          activo: c.activo,
          nivel: NivelProactividad.fromJson(c.nivel),
          leadLibreMin: c.leadLibreMin,
        );
      }
    } catch (_) {
      // Sin red / migración sin aplicar: dejamos el default (ON, exigente).
    }
  }

  Future<void> cambiarActivo(bool v) async {
    state = state.copyWith(activo: v);
    try {
      await _repo.actualizar(activo: v);
    } catch (_) {}
  }

  Future<void> cambiarNivel(NivelProactividad n) async {
    state = state.copyWith(nivel: n);
    try {
      await _repo.actualizar(nivel: n.toJson());
    } catch (_) {}
  }
}

final proactividadConfigProvider =
    StateNotifierProvider<ProactividadConfigController, ProactividadUiConfig>(
        (ref) {
  return ProactividadConfigController(ref.watch(proactividadRepositoryProvider));
});
