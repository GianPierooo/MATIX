import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matix/api/matix_client.dart';
import 'package:matix/features/matix/data/accion_dispositivo.dart';
import 'package:matix/features/matix/data/dispositivo_service.dart';
import 'package:matix/features/matix/data/matix_chat_repository.dart';
import 'package:matix/features/matix/domain/mensaje.dart';

/// Acciones de teléfono (Capa 6 · Fase 1): el cerebro PROPONE
/// `accion_dispositivo`; la app la parsea, respeta `requiere_confirmacion` y
/// mapea los datos al canal nativo. El cerebro nunca ejecuta.

class _FakeClient extends http.BaseClient {
  _FakeClient(this.respuesta);
  final Map<String, dynamic> respuesta;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(utf8.encode(json.encode(respuesta))),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AccionDispositivo.fromJson', () {
    test('parsea un mensaje que requiere confirmación', () {
      final acc = AccionDispositivo.fromJson({
        'tipo': 'mensaje',
        'datos': {'canal': 'whatsapp', 'texto': '¿nos vemos?'},
        'resumen': 'Enviar WhatsApp',
        'requiere_confirmacion': true,
      });
      expect(acc, isNotNull);
      expect(acc!.tipo, 'mensaje');
      expect(acc.datos['canal'], 'whatsapp');
      expect(acc.requiereConfirmacion, isTrue);
    });

    test('abrir/galería NO requieren confirmación', () {
      final abrir = AccionDispositivo.fromJson({
        'tipo': 'abrir',
        'datos': {'objetivo': 'url', 'valor': 'https://x.com'},
        'requiere_confirmacion': false,
      });
      expect(abrir!.requiereConfirmacion, isFalse);
    });

    test('por defecto requiere confirmación (defensa: campo ausente)', () {
      final acc = AccionDispositivo.fromJson({'tipo': 'llamada', 'datos': {}});
      expect(acc!.requiereConfirmacion, isTrue);
    });

    test('null/forma inválida → null (no rompe la app vieja)', () {
      expect(AccionDispositivo.fromJson(null), isNull);
      expect(AccionDispositivo.fromJson('texto'), isNull);
      expect(AccionDispositivo.fromJson({'datos': {}}), isNull); // sin tipo
    });
  });

  group('MatixChatRepository parsea accion_dispositivo', () {
    test('un turno con accion_dispositivo la expone en el ChatTurno', () async {
      final fake = _FakeClient({
        'respuesta': 'Listo, te preparo el WhatsApp.',
        'tools_usadas': ['redactar_mensaje'],
        'tablas_cambiadas': <String>[],
        'accion_dispositivo': {
          'tipo': 'mensaje',
          'datos': {'canal': 'whatsapp', 'texto': 'hola'},
          'resumen': 'Enviar WhatsApp',
          'requiere_confirmacion': true,
        },
      });
      final repo = MatixChatRepository(MatixClient(inner: fake));

      final turno = await repo.enviar(
        historial: const <Mensaje>[],
        mensaje: 'mándale wsp a María',
      );

      expect(turno.accionDispositivo, isNotNull);
      expect(turno.accionDispositivo!.tipo, 'mensaje');
      expect(turno.accionDispositivo!.requiereConfirmacion, isTrue);
    });

    test('un turno SIN accion_dispositivo → null', () async {
      final fake = _FakeClient({
        'respuesta': 'Hola',
        'tools_usadas': <String>[],
        'tablas_cambiadas': <String>[],
      });
      final repo = MatixChatRepository(MatixClient(inner: fake));
      final turno = await repo.enviar(historial: const [], mensaje: 'hola');
      expect(turno.accionDispositivo, isNull);
    });
  });

  group('DispositivoService mapea al canal nativo', () {
    const canal = MethodChannel('dev.matix.matix/dispositivo');
    late List<MethodCall> llamadas;
    late DispositivoService servicio;

    setUp(() {
      llamadas = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(canal, (call) async {
        llamadas.add(call);
        return true; // el Intent se lanzó
      });
      servicio = DispositivoService(canal: canal);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(canal, null);
    });

    test('mensaje → redactarMensaje con sus argumentos', () async {
      final r = await servicio.ejecutar('mensaje', {
        'canal': 'whatsapp',
        'destinatario': 'María',
        'texto': '¿nos vemos?',
      });
      expect(r.exito, isTrue);
      expect(llamadas.single.method, 'redactarMensaje');
      expect(llamadas.single.arguments['canal'], 'whatsapp');
      expect(llamadas.single.arguments['texto'], '¿nos vemos?');
    });

    test('evento → crearEvento con las fechas ISO convertidas a millis', () async {
      const iso = '2026-06-10T15:00:00Z';
      await servicio.ejecutar('evento', {
        'titulo': 'Dentista',
        'inicia_en': iso,
      });
      expect(llamadas.single.method, 'crearEvento');
      expect(
        llamadas.single.arguments['iniciaEnMillis'],
        DateTime.parse(iso).millisecondsSinceEpoch,
      );
      expect(llamadas.single.arguments['terminaEnMillis'], isNull);
    });

    test('abrir → abrir con objetivo/valor', () async {
      await servicio.ejecutar('abrir', {'objetivo': 'url', 'valor': 'https://x.com'});
      expect(llamadas.single.method, 'abrir');
      expect(llamadas.single.arguments['objetivo'], 'url');
    });

    test('si el nativo devuelve false → fallo con mensaje (degradación)', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(canal, (call) async => false);
      final r = await servicio.ejecutar('llamada', {'numero': '999'});
      expect(r.exito, isFalse);
      expect(r.mensaje, isNotNull);
    });

    test('PlatformException → fallo, nunca crashea', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(canal, (call) async {
        throw PlatformException(code: 'X', message: 'boom');
      });
      final r = await servicio.ejecutar('abrir', {'objetivo': 'url', 'valor': 'x'});
      expect(r.exito, isFalse);
    });
  });
}
