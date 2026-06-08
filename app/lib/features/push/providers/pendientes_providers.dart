import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../domain/pendientes_confirmacion.dart';

/// Trae el set determinista de pendientes de confirmar (ver
/// `cerebro/app/routers/push.py::pendientes_confirmacion`).
final pendientesConfirmacionProvider =
    FutureProvider<PendientesConfirmacion>((ref) async {
  final client = ref.watch(matixClientProvider);
  try {
    final j = await client.getOne('/api/v1/push/pendientes-confirmacion');
    return PendientesConfirmacion.fromJson(j);
  } catch (_) {
    // En MagicOS sin red puede tardar; degradamos a "vacío" en vez de error
    // ruidoso. El refresh manual lo reintenta. Nunca rompe la pantalla.
    return PendientesConfirmacion.vacia;
  }
});
