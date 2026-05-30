// El builder de filas arma el map con `if (x != null) 'k': x`, igual que
// el repo de tareas; suprimimos el lint como allá.
// ignore_for_file: use_null_aware_elements

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/api/matix_client.dart';
import 'package:matix/core/notificaciones_service.dart';
import 'package:matix/features/tareas/data/tareas_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regresión del crash al APLICAR el plan del día: al fijar el bloque de
/// cada tarea, el repo cancela/reprograma su recordatorio. Si el plugin
/// de notificaciones revienta (caía con "Missing type parameter" en la
/// build minificada), `actualizar`/`crear` NO deben propagar: la tarea
/// (y por tanto el bloque) se guarda igual. Acá el servicio de notifs
/// SIEMPRE lanza, y verificamos que el CRUD sobrevive.

class _NotifQueRevienta implements NotificacionesService {
  int cancelarLlamadas = 0;
  int programarLlamadas = 0;

  PlatformException _boom() => PlatformException(
        code: 'error',
        message: 'Missing type parameter.',
      );

  @override
  Future<void> cancelar(int id) async {
    cancelarLlamadas++;
    throw _boom();
  }

  @override
  Future<bool> programar({
    required int id,
    required String titulo,
    required String cuerpo,
    required DateTime cuando,
    bool exacto = false,
    String? payload,
  }) async {
    programarLlamadas++;
    throw _boom();
  }

  @override
  Future<bool> pedirPermisos() async => true;

  // El resto de la interfaz no la toca este flujo.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements MatixClient {
  Map<String, dynamic> _tarea({
    String id = 't1',
    String titulo = 'Avanzar tesis',
    String? bloqueInicio,
    String? bloqueFin,
  }) =>
      {
        'id': id,
        'titulo': titulo,
        'prioridad': 'media',
        'completada': false,
        'creada_en': '2026-05-30T10:00:00Z',
        'actualizada_en': '2026-05-30T10:00:00Z',
        if (bloqueInicio != null) 'bloque_inicio': bloqueInicio,
        if (bloqueFin != null) 'bloque_fin': bloqueFin,
      };

  @override
  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) async =>
      _tarea(
        bloqueInicio: body['bloque_inicio'] as String?,
        bloqueFin: body['bloque_fin'] as String?,
      );

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async =>
      _tarea(titulo: body['titulo'] as String? ?? 'Nueva');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('aplicar bloque (actualizar) no crashea aunque las notifs revienten',
      () async {
    final notif = _NotifQueRevienta();
    final repo = TareasRepository(_FakeClient(), notif);

    final t = await repo.actualizar('t1', {
      'bloque_inicio': '2026-05-30T14:00:00Z',
      'bloque_fin': '2026-05-30T15:00:00Z',
    });

    // El bloque quedó aplicado pese a que cancelar/programar lanzaron.
    expect(t.bloqueInicio, isNotNull);
    expect(t.bloqueFin, isNotNull);
    expect(notif.cancelarLlamadas, greaterThan(0)); // se intentó, y se tragó
  });

  test('crear tampoco crashea aunque las notifs revienten', () async {
    final notif = _NotifQueRevienta();
    final repo = TareasRepository(_FakeClient(), notif);

    final t = await repo.crear(titulo: 'Avanzar tesis');
    expect(t.titulo, isNotEmpty);
  });
}
