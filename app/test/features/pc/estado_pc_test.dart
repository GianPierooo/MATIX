import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as test_http;
import 'package:matix/api/matix_client.dart';

/// Tests de `MatixClient.estadoPc()` — la fuente de verdad del indicador "PC"
/// y del botón "Recomprobar PC". Lo crítico: distinguir conectada / desconectada
/// / error-de-contacto, y absorber el parpadeo de ~1s reintentando UNA vez.

http.Response _json(Map<String, dynamic> m, [int code = 200]) => http.Response(
      json.encode(m),
      code,
      headers: {'Content-Type': 'application/json'},
    );

MatixClient _cliente(Future<http.Response> Function(http.Request) handler) =>
    MatixClient(inner: test_http.MockClient(handler));

void main() {
  test('conectada: 200 + conectado=true → (true, sin error)', () async {
    final c = _cliente((_) async => _json({'conectado': true}));
    final r = await c.estadoPc();
    expect(r.conectada, isTrue);
    expect(r.error, isNull);
  });

  test('desconectada limpia: 200 + conectado=false → (false, sin error)', () async {
    final c = _cliente((_) async => _json({'conectado': false}));
    final r = await c.estadoPc();
    expect(r.conectada, isFalse);
    expect(r.error, isNull); // llegó al cerebro; simplemente no hay agente
  });

  test('error de contacto: el GET lanza → error no nulo (no es culpa del agente)', () async {
    final c = _cliente((_) async => throw http.ClientException('sin red'));
    final r = await c.estadoPc();
    expect(r.conectada, isFalse);
    expect(r.error, isNotNull);
    expect(r.error, contains('No pude contactar'));
  });

  test('401 corta con motivo de auth y NO reintenta', () async {
    var llamadas = 0;
    final c = _cliente((_) async {
      llamadas++;
      return http.Response('no', 401);
    });
    final r = await c.estadoPc();
    expect(r.conectada, isFalse);
    expect(r.error, contains('autorizada'));
    expect(llamadas, 1); // auth rota: reintentar no ayuda
  });

  test('absorbe el blip: 1er intento false, 2do true → conectada', () async {
    var llamadas = 0;
    final c = _cliente((_) async {
      llamadas++;
      return _json({'conectado': llamadas >= 2});
    });
    final r = await c.estadoPc();
    expect(r.conectada, isTrue);
    expect(llamadas, 2);
  });

  test('pcConectada() delega en estadoPc y devuelve el bool', () async {
    final c = _cliente((_) async => _json({'conectado': true}));
    expect(await c.pcConectada(), isTrue);
  });
}
