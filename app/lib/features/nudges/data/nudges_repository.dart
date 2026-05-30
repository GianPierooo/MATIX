import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../../core/providers.dart';

/// Config de nudges que vive en el CEREBRO (Push Capa 3b): maestro on/off,
/// horas de silencio y la disponibilidad por día (que el scheduler
/// respeta). La app la lee y la sincroniza acá.
typedef NudgesServerConfig = ({bool activo, int silencioInicio, int silencioFin});

class NudgesRepository {
  NudgesRepository(this._client);
  final MatixClient _client;

  Future<NudgesServerConfig?> obtener() async {
    final j = await _client.getOne('/api/v1/nudges');
    return (
      activo: j['activo'] as bool? ?? true,
      silencioInicio: (j['silencio_inicio'] as num?)?.toInt() ?? 22,
      silencioFin: (j['silencio_fin'] as num?)?.toInt() ?? 8,
    );
  }

  /// Actualiza solo los campos dados. `disponibilidad` es el mapa por día
  /// ISO ({"1":{"activo":true,"inicio":8,"fin":22}, …}) que sincroniza la
  /// pantalla de Disponibilidad.
  Future<void> actualizar({
    bool? activo,
    int? silencioInicio,
    int? silencioFin,
    Map<String, dynamic>? disponibilidad,
  }) async {
    final body = <String, dynamic>{};
    if (activo != null) body['activo'] = activo;
    if (silencioInicio != null) body['silencio_inicio'] = silencioInicio;
    if (silencioFin != null) body['silencio_fin'] = silencioFin;
    if (disponibilidad != null) body['disponibilidad'] = disponibilidad;
    if (body.isEmpty) return;
    await _client.patch('/api/v1/nudges', body);
  }
}

final nudgesRepositoryProvider = Provider<NudgesRepository>(
  (ref) => NudgesRepository(ref.watch(matixClientProvider)),
);
