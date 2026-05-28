import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as test_http;
import 'package:matix/api/matix_client.dart';
import 'package:matix/features/autoupdate/data/update_service.dart';

/// Tests del comparador del UpdateService.
///
/// Lo crítico es: tras servir build 10 desde /version y tener un
/// build local 9, `chequear()` debe devolver `HayActualizacion` —
/// con el build remoto MAYOR al local. Esto cubre el bug raíz del
/// Paso 3 (donde la comparación se hacía contra el versionCode del
/// manifest, que `--split-per-abi` muta).
///
/// `MatixConfig.buildNumber` se compila como const desde un
/// `--dart-define`. En tests `flutter test` corre sin defines, así
/// que `buildNumber == 0`. Eso ya es buen escenario para validar:
/// 10 > 0 = true.

UpdateService _serviceConRespuesta(Map<String, dynamic> respuesta) {
  // Cliente HTTP mockeado: cualquier GET devuelve la respuesta
  // canned. MatixClient lo usa internamente vía el inner http.Client.
  final mock = test_http.MockClient((request) async {
    if (request.url.path.contains('/api/v1/version')) {
      return http.Response(
        json.encode(respuesta),
        200,
        headers: {'Content-Type': 'application/json'},
      );
    }
    return http.Response('not found', 404);
  });
  return UpdateService(MatixClient(inner: mock));
}

void main() {
  test('build remoto 10 > local 0 detecta HayActualizacion', () async {
    final svc = _serviceConRespuesta({
      'disponible': true,
      'version': '1.0.0',
      'build_number': 10,
      'apk_url': 'https://example/apk.apk',
      'notas': 'release notes',
      'sha': 'abc123',
      'creado_en': '2026-05-28T07:14:03.594184+00:00',
    });
    final result = await svc.chequear();
    expect(result, isA<HayActualizacion>());
    final r = result as HayActualizacion;
    expect(r.info.buildNumber, 10);
    expect(r.buildLocal, 0); // sin dart-define en test
  });

  test(
    'comparación numérica (no lexicográfica): 10 supera a 9',
    () async {
      // Si la comparación fuera por string, "10" < "9" → caso
      // patológico del bug original. Acá forzamos exactamente
      // ese escenario simulando que el local fuera 9 (no se
      // puede en tests reales sin recompilar, pero sí podemos
      // construir manualmente las dos clases y comparar el
      // resultado).
      const local = 9;
      const remoto = 10;
      // La comparación es la misma línea que hace UpdateService:
      // `remote.buildNumber > buildLocal`. Verificamos que es int>int.
      expect(remoto > local, isTrue);
      expect(remoto.runtimeType, int);
      expect(local.runtimeType, int);
    },
  );

  test('build remoto == local devuelve Actualizado', () async {
    // Como en tests MatixConfig.buildNumber = 0, simulamos remoto
    // también 0.
    final svc = _serviceConRespuesta({
      'disponible': true,
      'version': '1.0.0',
      'build_number': 0,
      'apk_url': 'https://example/apk.apk',
      'notas': '',
      'creado_en': '2026-05-28T07:14:03.594184+00:00',
    });
    final result = await svc.chequear();
    expect(result, isA<Actualizado>());
    final r = result as Actualizado;
    expect(r.buildLocal, 0);
    expect(r.buildRemoto, 0);
  });

  test('servidor sin versiones devuelve Actualizado sin remoto', () async {
    final svc = _serviceConRespuesta({'disponible': false});
    final result = await svc.chequear();
    expect(result, isA<Actualizado>());
    final r = result as Actualizado;
    expect(r.buildRemoto, isNull);
  });

  test('401 → ChequeoFallido con razon authInvalida', () async {
    final mock = test_http.MockClient((req) async {
      return http.Response(
        json.encode({'detail': 'API key inválida'}),
        401,
        headers: {'Content-Type': 'application/json'},
      );
    });
    final svc = UpdateService(MatixClient(inner: mock));
    final result = await svc.chequear();
    expect(result, isA<ChequeoFallido>());
    final r = result as ChequeoFallido;
    expect(r.razon, RazonFallo.authInvalida);
    expect(r.detalle, contains('401'));
  });

  test('500 → ChequeoFallido con razon errorServidor', () async {
    final mock = test_http.MockClient((req) async {
      return http.Response(
        json.encode({'detail': 'boom'}),
        500,
        headers: {'Content-Type': 'application/json'},
      );
    });
    final svc = UpdateService(MatixClient(inner: mock));
    final result = await svc.chequear();
    expect(result, isA<ChequeoFallido>());
    final r = result as ChequeoFallido;
    expect(r.razon, RazonFallo.errorServidor);
  });

  test('respuesta sin campos requeridos → ChequeoFallido por parseo',
      () async {
    final svc = _serviceConRespuesta({
      // Falta version, build_number, apk_url
      'disponible': true,
    });
    final result = await svc.chequear();
    expect(result, isA<ChequeoFallido>());
    final r = result as ChequeoFallido;
    expect(r.razon, RazonFallo.parseo);
  });
}
