import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matix/api/matix_client.dart';
import 'package:matix/features/matix/data/matix_chat_repository.dart';
import 'package:matix/features/matix/domain/mensaje.dart';

/// Tests del `MatixChatRepository` para el chat multimodal: que la
/// imagen (data URL) viaje en el body cuando se adjunta, y que NO
/// aparezca cuando no hay imagen.

class _FakeClient extends http.BaseClient {
  Map<String, dynamic>? bodyEnviado;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final r = request as http.Request;
    bodyEnviado = json.decode(r.body) as Map<String, dynamic>;
    return http.StreamedResponse(
      Stream.value(utf8.encode(json.encode({
        'respuesta': 'Veo la imagen.',
        'tools_usadas': <String>[],
        'tablas_cambiadas': <String>[],
      }))),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

void main() {
  test('adjunta `imagen` (data URL) en el body cuando hay imagen', () async {
    final fake = _FakeClient();
    final repo = MatixChatRepository(MatixClient(inner: fake));
    const dataUrl = 'data:image/jpeg;base64,/9j/4AAQ==';

    final turno = await repo.enviar(
      historial: const <Mensaje>[],
      mensaje: 'mira esto',
      imagenDataUrl: dataUrl,
    );

    expect(turno.respuesta, 'Veo la imagen.');
    expect(fake.bodyEnviado!['mensaje'], 'mira esto');
    expect(fake.bodyEnviado!['imagen'], dataUrl);
  });

  test('sin imagen, el body NO incluye la clave `imagen`', () async {
    final fake = _FakeClient();
    final repo = MatixChatRepository(MatixClient(inner: fake));

    await repo.enviar(historial: const <Mensaje>[], mensaje: 'hola');

    expect(fake.bodyEnviado!.containsKey('imagen'), isFalse);
  });
}
