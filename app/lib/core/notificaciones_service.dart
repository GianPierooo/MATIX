import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;
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

  /// Callback que dispara al tocar una notificación. El payload es
  /// el string que se le pasó al programar (Capa 8 reducida usa
  /// `'briefing'` para abrir la pantalla del briefing). Si el
  /// payload es null o no hay handler registrado, no pasa nada.
  void Function(String? payload)? _onTapHandler;

  /// Registra el handler que se invocará al tocar una notificación.
  /// Llamar desde `main`/`MatixApp.initState` con un callback que
  /// usa un `GlobalKey<NavigatorState>` para navegar.
  void registrarOnTap(void Function(String? payload) handler) {
    _onTapHandler = handler;
  }

  Future<void> inicializar() async {
    if (_inicializado) return;
    try {
      // 1) Timezone — sin esto, `zonedSchedule` no puede programar.
      tz_data.initializeTimeZones();
      // La zona horaria por defecto del usuario es Lima (Documento
      // Maestro). En Capa 4+ se podría leer la del perfil.
      tz.setLocalLocation(tz.getLocation('America/Lima'));

      // 2) Plugin — con handler de tap para deep-links (briefing matutino,
      // futuras notificaciones contextuales).
      const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: initAndroid);
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (resp) {
          _onTapHandler?.call(resp.payload);
        },
      );

      // 3) Crear el canal explícitamente. Aunque el plugin lo crea al
      // primer `zonedSchedule`, hacerlo acá garantiza que exista (si no,
      // en algunos OEM la notificación no se muestra) y es idempotente.
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _canalId,
          _canalNombre,
          description: _canalDescripcion,
          importance: Importance.high,
        ),
      );
    } catch (e) {
      // Nunca dejamos que un fallo de init (timezone, canal, o una caché
      // de notificaciones ilegible del plugin) tumbe al caller. La app
      // sigue; solo puede que no lleguen avisos hasta el próximo arranque.
      debugPrint('Notif: inicializar falló ($e). Sigo en modo degradado.');
    } finally {
      // Marcamos inicializado pase lo que pase: no reintentamos en loop.
      _inicializado = true;
    }
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

  /// Pide el permiso de alarmas exactas (Android 12+). Sin él, las
  /// notificaciones `exacto: true` caen al modo inexacto. Abre la
  /// pantalla del sistema; en Android 13+ con `USE_EXACT_ALARM` el
  /// permiso ya viene concedido y esto suele ser innecesario.
  Future<bool> pedirPermisoAlarmasExactas() async {
    if (!Platform.isAndroid) return true;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    final granted = await android.requestExactAlarmsPermission();
    return granted ?? false;
  }

  /// Programa una notificación que dispara en `cuando` (zona del
  /// usuario). Si ya existía una con el mismo `id`, la reemplaza.
  ///
  /// `exacto`: usa `exactAllowWhileIdle` para que dispare al minuto. Si
  /// el sistema rechaza la alarma exacta (permiso revocado en Android
  /// 12), reintenta en modo inexacto en vez de propagar el error.
  /// `payload`: string que recibe el handler de tap (deep link).
  ///
  /// Devuelve `true` si se programó. Si `cuando` ya pasó, devuelve
  /// `false` y no programa nada (no tiene sentido recordar algo que
  /// ya pasó).
  Future<bool> programar({
    required int id,
    required String titulo,
    required String cuerpo,
    required DateTime cuando,
    bool exacto = false,
    String? payload,
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

    Future<void> agendar(AndroidScheduleMode modo) => _plugin.zonedSchedule(
          id,
          titulo,
          cuerpo,
          zoned,
          detalles,
          androidScheduleMode: modo,
          // El parámetro es requerido por el API aunque solo aplica a iOS
          // antes de iOS 10 (legacy). Como solo apuntamos Android, da
          // igual el valor — usamos el equivalente al reloj del sistema.
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
          // Sin `matchDateTimeComponents` — la repetición no se gestiona
          // aquí (la repetición de tareas la maneja el cerebro creando una
          // nueva fila al completar; este servicio solo programa instantes
          // puntuales).
        );

    final modo = exacto
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    try {
      try {
        await agendar(modo);
      } on PlatformException {
        // El permiso de alarma exacta puede estar revocado: degradamos a
        // inexacta para que el aviso igual llegue (con menos precisión).
        if (!exacto) rethrow;
        await agendar(AndroidScheduleMode.inexactAllowWhileIdle);
      }
    } catch (e) {
      // Falla de plataforma no recuperable del plugin (p.ej. la caché de
      // notificaciones quedó ilegible: "Missing type parameter"). NO la
      // propagamos: la tarea/bloque que nos llamó debe crearse igual —
      // solo no llega este aviso. El resto de notifs se reparan solas en
      // la próxima programación.
      debugPrint('Notif: no pude programar $id ($e). Sigo sin avisar.');
      return false;
    }
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
    String? payload,
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

    try {
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
        payload: payload,
      );
    } catch (e) {
      // Igual que `programar`: no abortamos al caller por una falla del
      // plugin (caché ilegible, OEM raro). El ajuste que la disparó
      // (p.ej. el cierre diario) queda guardado igual.
      debugPrint('Notif: no pude programar la diaria $id ($e).');
    }
  }

  /// Cancela la notificación con ese `id` (no falla si no existía).
  ///
  /// Internamente el plugin lee su caché de notificaciones programadas
  /// (Gson). Si esa lectura revienta — pasó al aplicar el plan del día
  /// con una build minificada sin reglas R8: "Missing type parameter" —
  /// NO propagamos: cancelar un aviso nunca debe tumbar el flujo que nos
  /// llamó (crear el bloque, completar la tarea…).
  Future<void> cancelar(int id) async {
    if (!_inicializado) await inicializar();
    try {
      await _plugin.cancel(id);
    } catch (e) {
      debugPrint('Notif: no pude cancelar $id ($e). Sigo.');
    }
  }

  /// Cancela todas las notificaciones programadas. Útil al cerrar
  /// sesión o al hacer reset completo.
  Future<void> cancelarTodo() async {
    if (!_inicializado) await inicializar();
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('Notif: no pude cancelar todo ($e). Sigo.');
    }
  }

  /// Lista los ids actualmente programados (útil para diagnóstico y
  /// para una eventual reconciliación contra los `recordar_en` de la
  /// BD). Ante una falla del plugin devuelve lista vacía en vez de
  /// propagar.
  Future<List<int>> pendientes() async {
    if (!_inicializado) await inicializar();
    try {
      final pend = await _plugin.pendingNotificationRequests();
      return pend.map((p) => p.id).toList(growable: false);
    } catch (e) {
      debugPrint('Notif: no pude listar pendientes ($e).');
      return const [];
    }
  }
}

/// Provider singleton del servicio. La inicialización (carga de
/// timezones + plugin) se hace lazy en el primer uso.
final notificacionesServiceProvider =
    Provider<NotificacionesService>((ref) => NotificacionesService());
