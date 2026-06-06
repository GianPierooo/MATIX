import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/matix_client.dart';

/// Cliente HTTP del cerebro, compartido por toda la app.
///
/// `Provider` (no autoDispose) — la conexión vive lo que dure la app.
/// Al cerrarse, libera el `http.Client` interno.
final matixClientProvider = Provider<MatixClient>((ref) {
  final client = MatixClient();
  ref.onDispose(client.close);
  return client;
});

/// Estado de conexión de la PC (agente local · Capa 6 · 6.0a).
///
/// `FutureProvider.autoDispose` — se recalcula al entrar a Ajustes y al
/// refrescar (`ref.invalidate`). Devuelve `true` si la PC está conectada.
final pcConectadaProvider = FutureProvider.autoDispose<bool>((ref) async {
  return ref.read(matixClientProvider).pcConectada();
});
