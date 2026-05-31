import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../../core/providers.dart';

/// Un modo de Matix: bundle que ajusta tono + conocimiento + prioridades.
/// Vive como `.md` en el cerebro; acá solo lo mostramos y lo activamos.
class ModoMatix {
  const ModoMatix({
    required this.nombre,
    required this.etiqueta,
    required this.descripcion,
  });

  /// Id interno (nombre del .md, ej. 'tesis').
  final String nombre;

  /// Nombre legible (ej. 'Tesis').
  final String etiqueta;
  final String descripcion;

  factory ModoMatix.fromJson(Map<String, dynamic> j) => ModoMatix(
        nombre: j['nombre'] as String,
        etiqueta: (j['etiqueta'] as String?) ?? (j['nombre'] as String),
        descripcion: (j['descripcion'] as String?) ?? '',
      );
}

/// Estado de modos: los disponibles + cuál está activo (null = normal).
typedef ModosEstado = ({List<ModoMatix> disponibles, String? activo});

/// Wrapper sobre `/api/v1/modos`. La fuente de verdad del modo activo es
/// el CEREBRO (lo inyecta al prompt); la app lo lee/cambia por acá.
class ModosRepository {
  ModosRepository(this._client);
  final MatixClient _client;

  Future<ModosEstado> estado() async =>
      _parse(await _client.getOne('/api/v1/modos'));

  Future<ModosEstado> activar(String modo) async =>
      _parse(await _client.post('/api/v1/modos/activar', {'modo': modo}));

  Future<ModosEstado> desactivar() async =>
      _parse(await _client.post('/api/v1/modos/desactivar', const {}));

  ModosEstado _parse(Map<String, dynamic> j) => (
        disponibles: (j['disponibles'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ModoMatix.fromJson)
            .toList(growable: false),
        activo: j['activo'] as String?,
      );
}

final modosRepositoryProvider = Provider<ModosRepository>(
  (ref) => ModosRepository(ref.watch(matixClientProvider)),
);
