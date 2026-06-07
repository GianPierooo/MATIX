import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notificaciones_service.dart';
import '../domain/intensidad_notif.dart';
import '../data/push_repository.dart';

/// Handler de push en BACKGROUND / app terminada. Top-level con
/// `@pragma('vm:entry-point')` porque corre en un isolate aparte.
///
/// Caso rendición de cuentas (`data.tipo == 'rendicion_cuentas'`): los pushes
/// del cerebro vienen como **data + notification** (la `notification` es el
/// fallback que el sistema muestra solo, sin botones). En este isolate sí
/// podemos repintar la notificación con `flutter_local_notifications` y sus
/// botones de acción → el usuario los ve aunque la app esté cerrada.
@pragma('vm:entry-point')
Future<void> manejarPushEnBackground(RemoteMessage message) async {
  try {
    final data = message.data;
    final tipo = data['tipo'];
    final titulo = message.notification?.title ?? 'Matix';
    final cuerpo = message.notification?.body ?? '';
    final acciones = ((data['acciones'] as String?) ?? '')
        .split(',')
        .where((a) => a.isNotEmpty)
        .toList();
    final intensidad = IntensidadNotif.fromJson(data['intensidad'] as String?);
    final critico = data['critico'] == 'true';
    if (acciones.isEmpty) return;
    final notif = NotificacionesService();
    await notif.inicializar();

    if (tipo == 'rendicion_cuentas') {
      final tareasIds = (data['tareas_ids'] as String?) ?? '';
      if (tareasIds.isEmpty) return;
      // Los botones actúan sobre UNA tarea (la primera); las demás caen por el
      // tick siguiente. Acciones únicas y atómicas, no batch.
      final primera = tareasIds.split(',').first;
      await notif.mostrarConAcciones(
        id: 990300,
        titulo: titulo,
        cuerpo: cuerpo,
        acciones: acciones,
        payload: 'rc:$primera',
        intensidad: intensidad,
        critico: critico,
      );
    } else if (tipo == 'asistencia_evento') {
      final eventoId = (data['evento_id'] as String?) ?? '';
      if (eventoId.isEmpty) return;
      await notif.mostrarConAcciones(
        id: 990400,
        titulo: titulo,
        cuerpo: cuerpo,
        acciones: acciones,
        payload: 'as:$eventoId',
        intensidad: intensidad,
        critico: critico,
      );
    }
  } catch (e) {
    debugPrint('Push BG: no pude repintar notif ($e).');
  }
}

/// Inicializa FCM: pide permiso, escucha mensajes en foreground (que FCM
/// NO muestra solo → los pintamos con el plugin local) y registra el token
/// del dispositivo en el cerebro. Best-effort: si algo falla, la app sigue.
class PushService {
  PushService(this._notif, this._repo);
  final NotificacionesService _notif;
  final PushRepository _repo;
  // Lazy: NO accedemos a la instancia en el constructor — si Firebase no
  // se inicializó (checkout sin google-services.json, tests), tocarla
  // tira. La usamos dentro del try de `inicializar`.
  FirebaseMessaging get _fm => FirebaseMessaging.instance;
  bool _listo = false;

  Future<void> inicializar() async {
    if (_listo) return;
    try {
      // Android 13+: pide POST_NOTIFICATIONS (igual que el plugin local).
      await _fm.requestPermission();

      // Foreground: FCM no dibuja la notificación; la mostramos nosotros
      // con el canal de Matix.
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n == null) return;
        final tipo = m.data['tipo'];
        final acciones = ((m.data['acciones'] as String?) ?? '')
            .split(',')
            .where((a) => a.isNotEmpty)
            .toList();
        final intensidad =
            IntensidadNotif.fromJson(m.data['intensidad'] as String?);
        final critico = m.data['critico'] == 'true';
        // Rendición de cuentas (tareas) → notif CON botones.
        if (tipo == 'rendicion_cuentas') {
          final tareasIds = (m.data['tareas_ids'] as String?) ?? '';
          if (tareasIds.isNotEmpty && acciones.isNotEmpty) {
            _notif.mostrarConAcciones(
              id: 990300,
              titulo: n.title ?? 'Matix',
              cuerpo: n.body ?? '',
              acciones: acciones,
              payload: 'rc:${tareasIds.split(',').first}',
              intensidad: intensidad,
              critico: critico,
            );
            return;
          }
        }
        // Asistencia a eventos → notif CON botones.
        if (tipo == 'asistencia_evento') {
          final eventoId = (m.data['evento_id'] as String?) ?? '';
          if (eventoId.isNotEmpty && acciones.isNotEmpty) {
            _notif.mostrarConAcciones(
              id: 990400,
              titulo: n.title ?? 'Matix',
              cuerpo: n.body ?? '',
              acciones: acciones,
              payload: 'as:$eventoId',
              intensidad: intensidad,
              critico: critico,
            );
            return;
          }
        }
        _notif.mostrarAhora(
          id: 990200,
          titulo: n.title ?? 'Matix',
          cuerpo: n.body ?? '',
          payload: m.data['payload'] as String?,
        );
      });

      // Token de este dispositivo → al cerebro.
      final token = await _fm.getToken();
      if (token != null) await _registrarSeguro(token);
      // Si el token rota, lo re-registramos.
      _fm.onTokenRefresh.listen(_registrarSeguro);

      _listo = true;
    } catch (e) {
      debugPrint('Push: init falló ($e). La app sigue sin push.');
    }
  }

  Future<void> _registrarSeguro(String token) async {
    try {
      await _repo.registrarToken(token);
    } catch (e) {
      debugPrint('Push: no pude registrar el token ($e).');
    }
  }
}

final pushServiceProvider = Provider<PushService>(
  (ref) => PushService(
    ref.watch(notificacionesServiceProvider),
    ref.watch(pushRepositoryProvider),
  ),
);
