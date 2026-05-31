import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/modelos_repository.dart';

/// Estado del selector de modelo: el catálogo + cuál está seleccionado +
/// el par barato/fuerte del modo Automático.
class ModelosState {
  const ModelosState({
    this.modelos = const [],
    this.seleccionado = '',
    this.barato = 'gpt-4o-mini',
    this.fuerte = 'claude-sonnet-4-6',
    this.cargando = false,
  });

  final List<ModeloLlm> modelos;
  final String seleccionado;
  final String barato;
  final String fuerte;
  final bool cargando;

  /// ¿Está activo el modo Automático?
  bool get esAuto => seleccionado == kModeloAuto;

  /// Los modelos agrupados por proveedor, en el orden del catálogo.
  Map<String, List<ModeloLlm>> get porProveedor {
    final out = <String, List<ModeloLlm>>{};
    for (final m in modelos) {
      out.putIfAbsent(m.proveedor, () => []).add(m);
    }
    return out;
  }

  ModeloLlm? porId(String id) {
    for (final m in modelos) {
      if (m.id == id) return m;
    }
    return null;
  }

  ModeloLlm? get modeloActual => porId(seleccionado);

  /// Etiqueta amigable de un id (cae al id si no está en el catálogo).
  String etiquetaDe(String id) => porId(id)?.etiqueta ?? id;

  ModelosState copyWith({
    List<ModeloLlm>? modelos,
    String? seleccionado,
    String? barato,
    String? fuerte,
    bool? cargando,
  }) {
    return ModelosState(
      modelos: modelos ?? this.modelos,
      seleccionado: seleccionado ?? this.seleccionado,
      barato: barato ?? this.barato,
      fuerte: fuerte ?? this.fuerte,
      cargando: cargando ?? this.cargando,
    );
  }
}

class ModelosController extends StateNotifier<ModelosState> {
  ModelosController(this._repo) : super(const ModelosState(cargando: true)) {
    _ready = _cargar();
  }

  final ModelosRepository _repo;
  late final Future<void> _ready;
  Future<void> get ready => _ready;

  ModelosState _desde(ModelosEstado e) => ModelosState(
        modelos: e.modelos,
        seleccionado: e.seleccionado,
        barato: e.barato,
        fuerte: e.fuerte,
      );

  Future<void> _cargar() async {
    try {
      state = _desde(await _repo.estado());
    } catch (_) {
      state = const ModelosState();
    }
  }

  Future<void> seleccionar(String id) async {
    if (id == state.seleccionado) return;
    final previo = state;
    // Optimista: marca ya el elegido; si falla, revierte.
    state = state.copyWith(seleccionado: id);
    try {
      state = _desde(await _repo.seleccionar(id));
    } catch (_) {
      state = previo;
    }
  }

  /// Cambia el par barato/fuerte del modo Automático.
  Future<void> fijarPar({String? barato, String? fuerte}) async {
    final previo = state;
    state = state.copyWith(barato: barato, fuerte: fuerte);
    try {
      state = _desde(await _repo.fijarPar(barato: barato, fuerte: fuerte));
    } catch (_) {
      state = previo;
    }
  }
}

final modelosProvider =
    StateNotifierProvider<ModelosController, ModelosState>((ref) {
  return ModelosController(ref.watch(modelosRepositoryProvider));
});
