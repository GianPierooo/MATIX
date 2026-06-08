import 'dart:async';

import 'package:http/http.dart' as http;

import 'confirmacion_service.dart';

/// Handler de un botón de la notificación de ASISTENCIA ("¿Fuiste a X?"),
/// disparado por `flutter_local_notifications` desde foreground o background
/// (app cerrada, isolate aparte sin Riverpod ni Firebase).
///
/// CONTRATO: no lanza nunca, no abre UI, hace `POST /push/asistencia/accion` y
/// termina. El cerebro marca `eventos.asistencia` (alimenta el motor de
/// evolución):
///   - 'si_fui'      → asistió.
///   - 'no_fui'      → no asistió.
///   - 'reprogramar' → no asistió + intención de reprogramar.
///
/// INSTRUMENTACIÓN (Honor/MagicOS): cada intento se anota en el log local de
/// [ConfirmacionService] para que la pantalla de Diagnóstico muestre evidencia.
///
/// CRÍTICO: TOP-LEVEL para que el isolate del background la invoque. URL y API
/// key vienen de `MatixConfig` (compile-time), sin estado de la app.
Future<void> manejarTapAsistencia({
  required String eventoId,
  required String accion,
  // Inyectable solo para tests; en producción usa el http.Client default.
  http.Client? cliente,
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (eventoId.isEmpty) return;
  final svc = ConfirmacionService(cliente: cliente);
  try {
    await svc.confirmarAsistencia(
      eventoId: eventoId, accion: accion, timeout: timeout,
    );
  } finally {
    if (cliente == null) svc.cerrar();
  }
}
