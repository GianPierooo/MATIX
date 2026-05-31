import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/modelos_repository.dart';

/// Estado del selector de modelo: el catálogo + cuál está seleccionado.
class ModelosState {
  const ModelosState({
    this.modelos = const [],
    this.seleccionado = '',
    this.cargando = false,
  });

  final List<ModeloLlm> modelos;
  final String seleccionado;
  final bool cargando;

  /// Los modelos agrupados por proveedor, en el orden del catálogo.
  Map<String, List<ModeloLlm>> get porProveedor {
    final out = <String, List<ModeloLlm>>{};
    for (final m in modelos) {
      out.putIfAbsent(m.proveedor, () => []).add(m);
    }
    return out;
  }

  ModeloLlm? get modeloActual {
    for (final m in modelos) {
      if (m.id == seleccionado) return m;
    }
    return null;
  }
}

class ModelosController extends StateNotifier<ModelosState> {
  ModelosController(this._repo) : super(const ModelosState(cargando: true)) {
    _ready = _cargar();
  }

  final ModelosRepository _repo;
  late final Future<void> _ready;
  Future<void> get ready => _ready;

  Future<void> _cargar() async {
    try {
      final e = await _repo.estado();
      state = ModelosState(modelos: e.modelos, seleccionado: e.seleccionado);
    } catch (_) {
      state = const ModelosState();
    }
  }

  Future<void> seleccionar(String id) async {
    if (id == state.seleccionado) return;
    final previo = state;
    // Optimista: marca ya el elegido; si falla, revierte.
    state = ModelosState(modelos: state.modelos, seleccionado: id);
    try {
      final e = await _repo.seleccionar(id);
      state = ModelosState(modelos: e.modelos, seleccionado: e.seleccionado);
    } catch (_) {
      state = previo;
    }
  }
}

final modelosProvider =
    StateNotifierProvider<ModelosController, ModelosState>((ref) {
  return ModelosController(ref.watch(modelosRepositoryProvider));
});
