import 'dart:async';

import 'package:http/http.dart' as http;

import 'confirmacion_service.dart';

/// Handler de un botón de acción de la notificación de rendición de cuentas,
/// disparado por `flutter_local_notifications` desde:
///   - foreground (la app está abierta), o
///   - background / app cerrada (isolate aparte, sin Riverpod ni Firebase).
///
/// CONTRATO: no lanza nunca, no abre UI, hace `POST /push/rendicion-cuentas/
/// accion` y termina. El cerebro:
///   - 'hecho'     → marca la tarea completada (idempotente).
///   - 'manana'    → rollover.aplicar_rollover(decision="otro_dia").
///   - 'mas_tarde' → mueve la tarea al próximo hueco real de HOY antes del
///                   ancla de dormir. Si no hay ventana útil, devuelve
///                   `tipo=sin_ventana` y aquí lo dejamos pasar limpio
///                   (la próxima notif ya no ofrecerá ese botón).
///
/// INSTRUMENTACIÓN (Honor/MagicOS): cada intento se anota en el log local de
/// [ConfirmacionService] para que la pantalla de Diagnóstico muestre evidencia
/// (último intento + status + error). Convierte "no sé por qué no funciona" en
/// "veo exactamente qué eslabón falla".
///
/// CRÍTICO: TOP-LEVEL para que el isolate del background la invoque. URL y API
/// key vienen de `MatixConfig` (compile-time), sin estado de la app.
Future<void> manejarTapRendicionCuentas({
  required String tareaId,
  required String accion,
  // Inyectable solo para tests. En producción usa el http.Client default.
  http.Client? cliente,
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (tareaId.isEmpty) return;
  // El servicio valida la acción y nunca lanza; aquí solo orquestamos.
  final svc = ConfirmacionService(cliente: cliente);
  try {
    await svc.confirmarTarea(
      tareaId: tareaId, accion: accion, timeout: timeout,
    );
  } finally {
    if (cliente == null) svc.cerrar();
  }
}
