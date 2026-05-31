import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/modos_repository.dart';

/// Estado de los modos de Matix en la app: la lista disponible + cuál está
/// activo. El indicador del chat lo observa.
class ModosState {
  const ModosState({
    this.disponibles = const [],
    this.activo,
    this.cargando = false,
  });

  final List<ModoMatix> disponibles;

  /// Nombre del modo activo, o null (modo normal).
  final String? activo;
  final bool cargando;

  /// El modo activo resuelto (con su etiqueta), o null si normal.
  ModoMatix? get modoActivo {
    if (activo == null) return null;
    for (final m in disponibles) {
      if (m.nombre == activo) return m;
    }
    return null;
  }

  ModosState _con({
    List<ModoMatix>? disponibles,
    String? activo,
    bool cargando = false,
  }) =>
      ModosState(
        disponibles: disponibles ?? this.disponibles,
        activo: activo,
        cargando: cargando,
      );
}

/// Maneja el modo activo. La fuente de verdad es el cerebro: cargamos al
/// arrancar, y persistimos cada cambio. El chat también lo actualiza
/// (`sincronizar`) cuando un turno reporta que el modelo cambió de modo.
class ModosController extends StateNotifier<ModosState> {
  ModosController(this._repo) : super(const ModosState(cargando: true)) {
    _ready = _cargar();
  }

  final ModosRepository _repo;
  late final Future<void> _ready;

  /// Completa cuando terminó el primer load desde el cerebro.
  Future<void> get ready => _ready;

  Future<void> _cargar() async {
    try {
      final e = await _repo.estado();
      state = ModosState(disponibles: e.disponibles, activo: e.activo);
    } catch (_) {
      // Sin red / migración sin aplicar: sin modos, modo normal.
      state = const ModosState();
    }
  }

  Future<void> activar(String modo) async {
    try {
      final e = await _repo.activar(modo);
      state = ModosState(disponibles: e.disponibles, activo: e.activo);
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> desactivar() async {
    try {
      final e = await _repo.desactivar();
      state = ModosState(disponibles: e.disponibles, activo: e.activo);
    } catch (_) {}
  }

  /// Sincroniza el modo activo con lo que reportó el cerebro tras un turno
  /// de chat (el modelo pudo activar/desactivar un modo con una tool). No
  /// le pega a la red: solo refleja el estado ya devuelto.
  void sincronizar(String? activoDelCerebro) {
    if (activoDelCerebro != state.activo) {
      state = state._con(activo: activoDelCerebro);
    }
  }
}

final modosProvider =
    StateNotifierProvider<ModosController, ModosState>((ref) {
  return ModosController(ref.watch(modosRepositoryProvider));
});
