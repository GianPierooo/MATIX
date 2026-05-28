import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/update_service.dart';

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService(ref.watch(matixClientProvider));
});

/// Resultado del chequeo al iniciar. Se computa una vez al abrir la
/// app (lazy: cuando el HomeShell lo `watch`-ea). Si la app sigue
/// abierta y querés re-chequear (botón "Buscar actualizaciones"
/// en Ajustes), `ref.invalidate(updateCheckProvider)`.
final updateCheckProvider = FutureProvider<UpdateCheckResult>((ref) async {
  final svc = ref.watch(updateServiceProvider);
  return svc.chequear();
});
