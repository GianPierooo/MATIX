import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../../core/providers.dart';

/// Config de un ritual diario (briefing / cierre): on/off + hora.
typedef RitualConfig = ({bool activo, int hora, int minuto});

/// La config de los rituales vive en el CEREBRO (Push Capa 3a): el
/// scheduler la usa para disparar el push a la hora correcta. La app la
/// lee y la edita por acá. No hay SharedPreferences: el server es la
/// fuente de verdad (por eso pueden venir activados por defecto).
class RitualesRepository {
  RitualesRepository(this._client);
  final MatixClient _client;

  /// Devuelve la config de `ritual` ('briefing' | 'cierre'), o null si el
  /// cerebro no la tiene (migración 0018 sin aplicar).
  Future<RitualConfig?> obtener(String ritual) async {
    final lista = await _client.getList('/api/v1/rituales');
    for (final r in lista.cast<Map<String, dynamic>>()) {
      if (r['ritual'] == ritual) {
        return (
          activo: r['activo'] as bool? ?? true,
          hora: (r['hora'] as num?)?.toInt() ?? 0,
          minuto: (r['minuto'] as num?)?.toInt() ?? 0,
        );
      }
    }
    return null;
  }

  Future<void> actualizar(
    String ritual, {
    required bool activo,
    required int hora,
    required int minuto,
  }) async {
    await _client.patch(
      '/api/v1/rituales/$ritual',
      {'activo': activo, 'hora': hora, 'minuto': minuto},
    );
  }
}

final ritualesRepositoryProvider = Provider<RitualesRepository>(
  (ref) => RitualesRepository(ref.watch(matixClientProvider)),
);
