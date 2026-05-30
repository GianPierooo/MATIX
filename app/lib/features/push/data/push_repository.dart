import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../../core/providers.dart';

/// Habla con el cerebro para el push (FCM · Capa 1): registra el token de
/// este dispositivo y dispara un push de prueba.
class PushRepository {
  PushRepository(this._client);
  final MatixClient _client;

  /// Guarda (upsert) el token de FCM en el cerebro para que pueda mandar
  /// push a este dispositivo.
  Future<void> registrarToken(String token,
      {String plataforma = 'android'}) async {
    await _client.post(
      '/api/v1/push/registrar-token',
      {'token': token, 'plataforma': plataforma},
    );
  }

  /// Pide al cerebro que mande un push de prueba a los tokens registrados.
  /// Devuelve `{enviados, fallidos, detalle}`.
  Future<Map<String, dynamic>> probar() {
    return _client.post('/api/v1/push/probar', const {});
  }
}

final pushRepositoryProvider = Provider<PushRepository>(
  (ref) => PushRepository(ref.watch(matixClientProvider)),
);
