import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../../core/providers.dart';

/// Config del motor de proactividad (Capa 8) que vive en el CEREBRO: el dial de
/// cuán proactivo es Matix (suave/equilibrado/exigente) + on/off. El scheduler
/// lo respeta en cada tick; la app la lee y la sincroniza acá.
typedef ProactividadServerConfig = ({bool activo, String nivel, int leadLibreMin});

class ProactividadRepository {
  ProactividadRepository(this._client);
  final MatixClient _client;

  Future<ProactividadServerConfig?> obtener() async {
    final j = await _client.getOne('/api/v1/proactividad');
    return (
      activo: j['activo'] as bool? ?? true,
      nivel: (j['nivel'] as String?) ?? 'exigente',
      leadLibreMin: (j['lead_libre_min'] as num?)?.toInt() ?? 30,
    );
  }

  /// Actualiza solo los campos dados.
  Future<void> actualizar({bool? activo, String? nivel, int? leadLibreMin}) async {
    final body = <String, dynamic>{};
    if (activo != null) body['activo'] = activo;
    if (nivel != null) body['nivel'] = nivel;
    if (leadLibreMin != null) body['lead_libre_min'] = leadLibreMin;
    if (body.isEmpty) return;
    await _client.patch('/api/v1/proactividad', body);
  }
}

final proactividadRepositoryProvider = Provider<ProactividadRepository>(
  (ref) => ProactividadRepository(ref.watch(matixClientProvider)),
);
