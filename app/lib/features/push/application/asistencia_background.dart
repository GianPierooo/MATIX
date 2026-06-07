import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../../../config.dart';

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
  if (accion != 'si_fui' && accion != 'no_fui' && accion != 'reprogramar') {
    return;
  }
  if (MatixConfig.apiUrl.isEmpty) return;

  final uri = Uri.parse('${MatixConfig.apiUrl}/api/v1/push/asistencia/accion');
  final headers = <String, String>{
    'Content-Type': 'application/json',
    if (MatixConfig.hasApiKey) 'X-Matix-Key': MatixConfig.apiKey,
  };
  final body = json.encode({'evento_id': eventoId, 'accion': accion});
  final c = cliente ?? http.Client();
  try {
    await c.post(uri, headers: headers, body: body).timeout(timeout);
  } catch (e) {
    // Sin red / 5xx: lo dejamos pasar limpio; el próximo tick re-evaluará.
    // NUNCA crashea (eso mataría el sistema de notificaciones).
    debugPrint('Asistencia background: no pude aplicar la acción ($e).');
  } finally {
    if (cliente == null) c.close();
  }
}
