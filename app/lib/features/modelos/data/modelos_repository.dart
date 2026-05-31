import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../../core/providers.dart';

/// Un modelo del LLM de chat (del catálogo curado del cerebro).
class ModeloLlm {
  const ModeloLlm({
    required this.id,
    required this.etiqueta,
    required this.proveedor,
  });

  final String id;
  final String etiqueta;

  /// 'openai' | 'anthropic'.
  final String proveedor;

  factory ModeloLlm.fromJson(Map<String, dynamic> j) => ModeloLlm(
        id: j['id'] as String,
        etiqueta: (j['etiqueta'] as String?) ?? (j['id'] as String),
        proveedor: (j['proveedor'] as String?) ?? 'openai',
      );

  /// Nombre legible del proveedor para los encabezados de la app.
  String get proveedorEtiqueta =>
      proveedor == 'anthropic' ? 'Anthropic (Claude)' : 'OpenAI (GPT)';
}

/// Catálogo + cuál está seleccionado.
typedef ModelosEstado = ({List<ModeloLlm> modelos, String seleccionado});

/// Wrapper sobre `/api/v1/modelos`. El catálogo y la selección viven en el
/// CEREBRO (que rutea al proveedor según el id); la app los lee y cambia.
class ModelosRepository {
  ModelosRepository(this._client);
  final MatixClient _client;

  Future<ModelosEstado> estado() async =>
      _parse(await _client.getOne('/api/v1/modelos'));

  Future<ModelosEstado> seleccionar(String id) async =>
      _parse(await _client.post('/api/v1/modelos/seleccionar', {'modelo': id}));

  ModelosEstado _parse(Map<String, dynamic> j) => (
        modelos: (j['modelos'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ModeloLlm.fromJson)
            .toList(growable: false),
        seleccionado: (j['seleccionado'] as String?) ?? '',
      );
}

final modelosRepositoryProvider = Provider<ModelosRepository>(
  (ref) => ModelosRepository(ref.watch(matixClientProvider)),
);
