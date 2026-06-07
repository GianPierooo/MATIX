import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matix/features/push/application/asistencia_background.dart';

/// El handler de background de la asistencia ("¿Fuiste a X?") NO debe lanzar
/// nunca (rompería el isolate del SO de notificaciones). Mismo contrato que el
/// de rendición de cuentas.
void main() {
  test('ignora eventoId vacío', () async {
    var llamado = false;
    final fake = MockClient((_) async {
      llamado = true;
      return http.Response('{}', 200);
    });
    await manejarTapAsistencia(eventoId: '', accion: 'si_fui', cliente: fake);
    expect(llamado, isFalse);
  });

  test('ignora acción desconocida', () async {
    var llamado = false;
    final fake = MockClient((_) async {
      llamado = true;
      return http.Response('{}', 200);
    });
    await manejarTapAsistencia(eventoId: 'e1', accion: 'tal_vez', cliente: fake);
    expect(llamado, isFalse);
  });

  test('POSTea las tres acciones con el body correcto', () async {
    final llamadas = <Map<String, dynamic>>[];
    final fake = MockClient((req) async {
      llamadas.add(json.decode(req.body) as Map<String, dynamic>);
      expect(req.url.path, '/api/v1/push/asistencia/accion');
      return http.Response('{"ok":true}', 200);
    });
    for (final a in ['si_fui', 'no_fui', 'reprogramar']) {
      await manejarTapAsistencia(eventoId: 'e1', accion: a, cliente: fake);
    }
    expect(llamadas, hasLength(3));
    expect(llamadas[0], {'evento_id': 'e1', 'accion': 'si_fui'});
    expect(llamadas[1], {'evento_id': 'e1', 'accion': 'no_fui'});
    expect(llamadas[2], {'evento_id': 'e1', 'accion': 'reprogramar'});
  });

  test('traga errores HTTP sin crashear (clave en background)', () async {
    final fake = MockClient((_) async => http.Response('boom', 500));
    await manejarTapAsistencia(eventoId: 'e1', accion: 'si_fui', cliente: fake);
  });

  test('traga timeouts sin crashear', () async {
    final fake = MockClient(
      (_) async => Future.delayed(
        const Duration(seconds: 5),
        () => http.Response('{}', 200),
      ),
    );
    await manejarTapAsistencia(
      eventoId: 'e1', accion: 'si_fui', cliente: fake,
      timeout: const Duration(milliseconds: 100),
    );
  });
}
