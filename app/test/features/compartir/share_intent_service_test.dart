import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/compartir/data/share_intent_service.dart';

/// Tests del `ShareIntentService` — el puente con MainActivity.kt para
/// "Compartir-a-Matix" (Capa 7). No hay nativo real en los tests:
/// mockeamos el MethodChannel.
///
/// - `getInitialSharedText` (Flutter → nativo): el texto del intent que
///   arrancó la app, trimmeado; vacío/espacios → null.
/// - `onSharedText` (nativo → Flutter): simulamos la invocación entrante
///   y verificamos que el callback recibe el texto.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.matix.matix/share');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('obtenerTextoInicial', () {
    test('devuelve el texto trimmeado del nativo', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getInitialSharedText') return '  hola mundo  ';
        return null;
      });

      final service = ShareIntentService();
      expect(await service.obtenerTextoInicial(), 'hola mundo');
    });

    test('null cuando no hay nada compartido', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      final service = ShareIntentService();
      expect(await service.obtenerTextoInicial(), isNull);
    });

    test('texto en blanco se trata como null', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => '   ');
      final service = ShareIntentService();
      expect(await service.obtenerTextoInicial(), isNull);
    });

    test('si el canal nativo falla, devuelve null sin romper', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'ERR', message: 'boom');
      });
      final service = ShareIntentService();
      expect(await service.obtenerTextoInicial(), isNull);
    });
  });

  group('escuchar', () {
    test('dispara el callback con el texto entrante', () async {
      final service = ShareIntentService();
      final recibidos = <String>[];
      service.escuchar(recibidos.add);

      await _simularEntrante(channel, 'https://ejemplo.com/post');

      expect(recibidos, ['https://ejemplo.com/post']);
    });

    test('ignora texto vacío entrante', () async {
      final service = ShareIntentService();
      final recibidos = <String>[];
      service.escuchar(recibidos.add);

      await _simularEntrante(channel, '   ');

      expect(recibidos, isEmpty);
    });

    test('trimmea el texto entrante', () async {
      final service = ShareIntentService();
      final recibidos = <String>[];
      service.escuchar(recibidos.add);

      await _simularEntrante(channel, '  nota rápida  ');

      expect(recibidos, ['nota rápida']);
    });
  });
}

/// Simula que el nativo invoca `onSharedText` sobre el canal (la app ya
/// estaba abierta). Empuja el mensaje al buffer del canal, igual que el
/// engine, y llega al handler que registró `escuchar`.
Future<void> _simularEntrante(MethodChannel channel, String texto) async {
  final completer = Completer<void>();
  ServicesBinding.instance.channelBuffers.push(
    channel.name,
    channel.codec.encodeMethodCall(MethodCall('onSharedText', texto)),
    (_) => completer.complete(),
  );
  await completer.future;
}
