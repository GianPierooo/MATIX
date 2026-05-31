// Mantenemos `if (x != null) 'k': x` por claridad (mismo patrón que el
// resto de repos). La sintaxis null-aware `?'k': x` hace lo mismo pero
// menos legible en este caso.
// ignore_for_file: use_null_aware_elements

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../../core/providers.dart';

/// Valor especial de la selección: modo "Automático" (el cerebro elige el
/// modelo por mensaje, con reglas). No es un id de modelo del catálogo.
const String kModeloAuto = 'auto';

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

/// Catálogo + selección + el par barato/fuerte del modo Automático.
///
/// `seleccionado` es un id del catálogo o el literal `'auto'`.
/// `barato`/`fuerte` son los ids del par que usa el modo Automático.
typedef ModelosEstado = ({
  List<ModeloLlm> modelos,
  String seleccionado,
  String barato,
  String fuerte,
});

/// Wrapper sobre `/api/v1/modelos`. El catálogo, la selección y el ruteo
/// (qué proveedor / qué modelo en auto) viven en el CEREBRO; la app los lee
/// y cambia.
class ModelosRepository {
  ModelosRepository(this._client);
  final MatixClient _client;

  Future<ModelosEstado> estado() async =>
      _parse(await _client.getOne('/api/v1/modelos'));

  Future<ModelosEstado> seleccionar(String id) async =>
      _parse(await _client.post('/api/v1/modelos/seleccionar', {'modelo': id}));

  /// Cambia el par barato/fuerte del modo Automático (cualquiera puede ir
  /// null para un cambio parcial).
  Future<ModelosEstado> fijarPar({String? barato, String? fuerte}) async =>
      _parse(await _client.post('/api/v1/modelos/par', {
        if (barato != null) 'barato': barato,
        if (fuerte != null) 'fuerte': fuerte,
      }));

  ModelosEstado _parse(Map<String, dynamic> j) {
    final par = (j['par'] as Map?)?.cast<String, dynamic>() ?? const {};
    return (
      modelos: (j['modelos'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(ModeloLlm.fromJson)
          .toList(growable: false),
      seleccionado: (j['seleccionado'] as String?) ?? '',
      barato: (par['barato'] as String?) ?? 'gpt-4o-mini',
      fuerte: (par['fuerte'] as String?) ?? 'claude-sonnet-4-6',
    );
  }
}

final modelosRepositoryProvider = Provider<ModelosRepository>(
  (ref) => ModelosRepository(ref.watch(matixClientProvider)),
);
