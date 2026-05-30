import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notificaciones_service.dart';
import '../data/push_repository.dart';

/// Handler de push en BACKGROUND / app terminada. Debe ser una función
/// top-level con `@pragma('vm:entry-point')` porque corre en un isolate
/// aparte. En Push Capa 1 no hace nada: los mensajes con bloque
/// `notification` los muestra el sistema solo (esa es justamente la gracia
/// del push frente a la notificación local que el OEM mata).
@pragma('vm:entry-point')
Future<void> manejarPushEnBackground(RemoteMessage message) async {
  // Intencionalmente vacío (Capa 1).
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
