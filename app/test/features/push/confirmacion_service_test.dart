import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matix/features/push/application/confirmacion_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El servicio NUNCA debe lanzar (es la espina dorsal del handler de background
/// + la UI in-app). Verificamos:
///   - acción válida → POST al endpoint correcto;
///   - argumentos inválidos → no toca la red, devuelve ok=false;
///   - status no-200 → ok=false con statusCode;
///   - excepción → ok=false con tipo del error;
///   - cada intento queda en el log local (instrumentación).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('confirmarTarea con acción válida POSTea al endpoint correcto', () async {
    final llamadas = <Map<String, dynamic>>[];
    final cliente = MockClient((req) async {
      llamadas.add({
        'path': req.url.path,
        'body': json.decode(req.body) as Map<String, dynamic>,
      });
      return http.Response('{"ok":true}', 200);
    });
    final svc = ConfirmacionService(cliente: cliente);
    final r = await svc.confirmarTarea(tareaId: 't1', accion: 'hecho');
    expect(r.ok, isTrue);
    expect(r.statusCode, 200);
    expect(llamadas.single['path'], '/api/v1/push/rendicion-cuentas/accion');
    expect(llamadas.single['body'], {'tarea_id': 't1', 'accion': 'hecho'});
    // Instrumentación: el intento quedó registrado.
    final log = await svc.leerLog();
    expect(log, hasLength(1));
    expect(log.first.tipo, TipoConfirmacion.tarea);
    expect(log.first.ok, isTrue);
    expect(log.first.statusCode, 200);
  });

  test('confirmarAsistencia con acción válida POSTea al endpoint correcto',
      () async {
    final llamadas = <Map<String, dynamic>>[];
    final cliente = MockClient((req) async {
      llamadas.add({
        'path': req.url.path,
        'body': json.decode(req.body) as Map<String, dynamic>,
      });
      return http.Response('{"ok":true}', 200);
    });
    final svc = ConfirmacionService(cliente: cliente);
    final r = await svc.confirmarAsistencia(eventoId: 'e1', accion: 'si_fui');
    expect(r.ok, isTrue);
    expect(llamadas.single['path'], '/api/v1/push/asistencia/accion');
    expect(llamadas.single['body'], {'evento_id': 'e1', 'accion': 'si_fui'});
  });

  test('argumentos inválidos NO tocan la red', () async {
    var hits = 0;
    final cliente = MockClient((_) async {
      hits++;
      return http.Response('{}', 200);
    });
    final svc = ConfirmacionService(cliente: cliente);
    expect((await svc.confirmarTarea(tareaId: '', accion: 'hecho')).ok, isFalse);
    expect((await svc.confirmarTarea(tareaId: 't1', accion: 'tal_vez')).ok,
        isFalse);
    expect((await svc.confirmarAsistencia(eventoId: '', accion: 'si_fui')).ok,
        isFalse);
    expect((await svc.confirmarAsistencia(eventoId: 'e1', accion: 'maybe')).ok,
        isFalse);
    expect(hits, 0);
  });

  test('status no-200 queda como ok=false con statusCode + error en el log',
      () async {
    final cliente =
        MockClient((_) async => http.Response('{"detail":"boom"}', 500));
    final svc = ConfirmacionService(cliente: cliente);
    final r = await svc.confirmarTarea(tareaId: 't1', accion: 'hecho');
    expect(r.ok, isFalse);
    expect(r.statusCode, 500);
    final log = await svc.leerLog();
    expect(log.first.ok, isFalse);
    expect(log.first.statusCode, 500);
    expect(log.first.error, contains('boom'));
  });

  test('excepción HTTP (red caída) queda como ok=false y el chain no crashea',
      () async {
    final cliente = MockClient((_) async => throw http.ClientException('red'));
    final svc = ConfirmacionService(cliente: cliente);
    final r = await svc.confirmarTarea(tareaId: 't1', accion: 'hecho');
    expect(r.ok, isFalse);
    final log = await svc.leerLog();
    expect(log.first.ok, isFalse);
    expect(log.first.error, contains('ClientException'));
  });

  test('log se trunca al tope (~30) — no crece indefinidamente', () async {
    final cliente = MockClient(
      (_) async => http.Response('{}', 200),
    );
    final svc = ConfirmacionService(cliente: cliente);
    for (var i = 0; i < 40; i++) {
      await svc.confirmarTarea(tareaId: 't$i', accion: 'hecho');
    }
    final log = await svc.leerLog();
    expect(log.length, lessThanOrEqualTo(30));
    // Las MÁS RECIENTES están al frente.
    expect(log.first.ref, 't39');
  });

  test('limpiarLog vacía el historial', () async {
    final cliente =
        MockClient((_) async => http.Response('{}', 200));
    final svc = ConfirmacionService(cliente: cliente);
    await svc.confirmarTarea(tareaId: 't1', accion: 'hecho');
    expect((await svc.leerLog()), isNotEmpty);
    await svc.limpiarLog();
    expect((await svc.leerLog()), isEmpty);
  });
}
