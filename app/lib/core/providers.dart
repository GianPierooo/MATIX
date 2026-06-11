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
