import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../../../config.dart';

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
/// CRÍTICO: debe ser una función TOP-LEVEL para que el isolate del background
/// la pueda invocar. La URL y la API key vienen de `MatixConfig` (compile-time
/// con `--dart-define`), así que tampoco necesitan estado de la app.
Future<void> manejarTapRendicionCuentas({
  required String tareaId,
  required String accion,
  // Inyectable solo para tests. En producción usa el http.Client default.
  http.Client? cliente,
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (tareaId.isEmpty) return;
  if (accion != 'hecho' && accion != 'manana' && accion != 'mas_tarde') return;
  if (MatixConfig.apiUrl.isEmpty) return;

  final uri = Uri.parse(
    '${MatixConfig.apiUrl}/api/v1/push/rendicion-cuentas/accion',
  );
  final headers = <String, String>{
    'Content-Type': 'application/json',
    if (MatixConfig.hasApiKey) 'X-Matix-Key': MatixConfig.apiKey,
  };
  final body = json.encode({'tarea_id': tareaId, 'accion': accion});
  final c = cliente ?? http.Client();
  try {
    // Timeout corto: el isolate de background tiene poco tiempo de vida.
    await c.post(uri, headers: headers, body: body).timeout(timeout);
  } catch (e) {
    // Sin red / 5xx: no podemos abrir la app aquí. Lo dejamos pasar limpio;
    // el próximo tick de rendición de cuentas del cerebro re-evaluará. NUNCA
    // crashea el handler — eso mataría al sistema de notificaciones.
    debugPrint('RC background: no pude aplicar la acción ($e).');
  } finally {
    // Solo cerramos el que creamos nosotros (el inyectado lo gestiona el caller).
    if (cliente == null) c.close();
  }
}
