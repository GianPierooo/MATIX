import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Servicio de notificaciones locales del Paso 11.
///
/// Modelo simple: el cerebro no envía push. La app programa una
/// `ScheduledNotification` por cada tarea / evento / evaluación que
/// tenga `recordar_en` no nulo, usando el `id` de la fila como
/// `notification_id` (estable, así puedo cancelar/reprogramar al
/// editar o completar).
///
/// Llamar a `inicializar()` UNA VEZ al arrancar la app (desde `main`).
/// El permiso runtime de Android 13+ se pide la primera vez que se
/// intenta programar — si el usuario lo niega, se devuelve `false` y
/// la app sigue funcionando sin notificación.
class NotificacionesService {
  NotificacionesService();

  static const _canalId = 'matix_recordatorios';
  static const _canalNombre = 'Recordatorios';
  static const _canalDescripcion =
      'Avisos antes de que venzan tareas, eventos y entregas.';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _inicializado = false;

  Future<void> inicializar() async {
    if (_inicializado) return;

    // 1) Timezone — sin esto, `zonedSchedule` no puede programar.
    tz_data.initializeTimeZones();
    // La zona horaria por defecto del usuario es Lima (Documento
    // Maestro). En Capa 4+ se podría leer la del perfil.
    tz.setLocalLocation(tz.getLocation('America/Lima'));

    // 2) Plugin
    const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: initAndroid);
    await _plugin.initialize(settings);

    _inicializado = true;
  }

  /// Pide los permisos relevantes para Android 13+. Devuelve `true` si
  /// el usuario los concedió (o si ya los tenía). En iOS / desktop /
  /// versiones de Android <13 devuelve `true` directamente.
  Future<bool> pedirPermisos() async {
    if (!Platform.isAndroid) return true;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    final granted = await android.requestNotificationsPermission();
    return granted ?? false;
  }

  /// Programa una notificación que dispara en `cuando` (zona del
  /// usuario). Si ya existía una con el mismo `id`, la reemplaza.
  ///
  /// Devuelve `true` si se programó. Si `cuando` ya pasó, devuelve
  /// `false` y no programa nada (no tiene sentido recordar algo que
  /// ya pasó).
  Future<bool> programar({
    required int id,
    required String titulo,
    required String cuerpo,
    required DateTime cuando,
  }) async {
    if (!_inicializado) await inicializar();
    final ahora = tz.TZDateTime.now(tz.local);
    final zoned = tz.TZDateTime.from(cuando, tz.local);
    if (!zoned.isAfter(ahora)) return false;

    const detalles = NotificationDetails(
      android: AndroidNotificationDetails(
        _canalId,
        _canalNombre,
        channelDescription: _canalDescripcion,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    await _plugin.zonedSchedule(
      id,
      titulo,
      cuerpo,
      zoned,
      detalles,
      // `inexactAllowWhileIdle` evita pedir permiso de alarmas exactas
      // (Android 12+). Si el usuario quiere precisión al minuto, se
      // cambia a `exactAllowWhileIdle` y se gestiona el permiso aparte.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // El parámetro es requerido por el API aunque solo aplica a iOS
      // antes de iOS 10 (legacy). Como solo apuntamos Android, da
      // igual el valor — usamos el equivalente al reloj del sistema.
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      // Sin `matchDateTimeComponents` — la repetición no se gestiona
      // aquí (la repetición de tareas la maneja el cerebro creando una
      // nueva fila al completar; este servicio solo programa instantes
      // puntuales).
    );
    return true;
  }

  /// Programa una notificación que se repite **cada día a la misma
  /// hora local**. Idempotente: re-programar con el mismo `id`
  /// sustituye la programación previa.
  ///
  /// Se usa para recordatorios fijos del usuario (p.ej. el cierre del
  /// día a las 21:30). Si la app pasa a segundo plano o se reinicia
  /// el teléfono, Android la dispara igual (los receivers del plugin
  /// se registran en el manifest).
  Future<void> programarDiaria({
    required int id,
    required String titulo,
    required String cuerpo,
    required int hora,
    required int minuto,
  }) async {
    if (!_inicializado) await inicializar();
    final ahora = tz.TZDateTime.now(tz.local);
    var primera = tz.TZDateTime(
      tz.local, ahora.year, ahora.month, ahora.day, hora, minuto,
    );
    // Si la hora de hoy ya pasó, programar para mañana.
    if (!primera.isAfter(ahora)) {
      primera = primera.add(const Duration(days: 1));
    }

    const detalles = NotificationDetails(
      android: AndroidNotificationDetails(
        _canalId,
        _canalNombre,
        channelDescription: _canalDescripcion,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    await _plugin.zonedSchedule(
      id,
      titulo,
      cuerpo,
      primera,
      detalles,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      // Repite cada día a la misma hora — el plugin la vuelve a
      // disparar sin que tengamos que reprogramarla.
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Cancela la notificación con ese `id` (no falla si no existía).
  Future<void> cancelar(int id) async {
    if (!_inicializado) await inicializar();
    await _plugin.cancel(id);
  }

  /// Cancela todas las notificaciones programadas. Útil al cerrar
  /// sesión o al hacer reset completo.
  Future<void> cancelarTodo() async {
    if (!_inicializado) await inicializar();
    await _plugin.cancelAll();
  }

  /// Lista los ids actualmente programados (útil para diagnóstico y
  /// para una eventual reconciliación contra los `recordar_en` de la
  /// BD).
  Future<List<int>> pendientes() async {
    if (!_inicializado) await inicializar();
    final pend = await _plugin.pendingNotificationRequests();
    return pend.map((p) => p.id).toList(growable: false);
  }
}

/// Provider singleton del servicio. La inicialización (carga de
/// timezones + plugin) se hace lazy en el primer uso.
final notificacionesServiceProvider =
    Provider<NotificacionesService>((ref) => NotificacionesService());
