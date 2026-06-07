import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matix/features/push/application/rendicion_cuentas_background.dart';

/// El handler de background de los botones de acción NO debe lanzar nunca:
/// rompería el isolate del SO de notificaciones y el siguiente push no se
/// entregaría. Tests verifican el contrato puro:
///   - Tarea vacía / acción desconocida → no llama al cerebro.
///   - Acciones válidas → POST al endpoint con el body correcto.
///   - Endpoint que falla → tragar el error sin crashear.
void main() {
  test('handler ignora tareaId vacío', () async {
    var llamado = false;
    final fake = MockClient((_) async {
      llamado = true;
      return http.Response('{}', 200);
    });
    await manejarTapRendicionCuentas(
      tareaId: '', accion: 'hecho', cliente: fake,
    );
    expect(llamado, isFalse);
  });

  test('handler ignora acción desconocida', () async {
    var llamado = false;
    final fake = MockClient((_) async {
      llamado = true;
      return http.Response('{}', 200);
    });
    await manejarTapRendicionCuentas(
      tareaId: 't1', accion: 'borrar', cliente: fake,
    );
    expect(llamado, isFalse);
  });

  test('handler POSTea las tres acciones con el body correcto', () async {
    final llamadas = <Map<String, dynamic>>[];
    final fake = MockClient((req) async {
      llamadas.add(json.decode(req.body) as Map<String, dynamic>);
      expect(req.url.path, '/api/v1/push/rendicion-cuentas/accion');
      return http.Response('{"ok":true}', 200);
    });
    for (final a in ['hecho', 'manana', 'mas_tarde']) {
      await manejarTapRendicionCuentas(
        tareaId: 't1', accion: a, cliente: fake,
      );
    }
    expect(llamadas, hasLength(3));
    expect(llamadas[0], {'tarea_id': 't1', 'accion': 'hecho'});
    expect(llamadas[1], {'tarea_id': 't1', 'accion': 'manana'});
    expect(llamadas[2], {'tarea_id': 't1', 'accion': 'mas_tarde'});
  });

  test('handler traga errores HTTP sin crashear (clave en background)', () async {
    final fake = MockClient((_) async => http.Response('boom', 500));
    // No lanza, aunque el server devuelva 500.
    await manejarTapRendicionCuentas(
      tareaId: 't1', accion: 'hecho', cliente: fake,
    );
  });

  test('handler traga timeouts sin crashear', () async {
    final fake = MockClient(
      (_) async => Future.delayed(
        const Duration(seconds: 5),
        () => http.Response('{}', 200),
      ),
    );
    // Timeout 100ms < delay 5s → debería tragar el TimeoutException.
    await manejarTapRendicionCuentas(
      tareaId: 't1', accion: 'hecho', cliente: fake,
      timeout: const Duration(milliseconds: 100),
    );
  });
}
