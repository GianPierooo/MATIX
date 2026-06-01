import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matix/api/matix_client.dart';
import 'package:matix/features/matix/data/matix_chat_repository.dart';
import 'package:matix/features/matix/domain/mensaje.dart';

/// Tests del `MatixChatRepository` para el chat multimodal: que las imágenes
/// (data URL) viajen en el body como lista `imagenes` cuando se adjuntan
/// (una o varias), y que NO aparezcan cuando no hay ninguna.

class _FakeClient extends http.BaseClient {
  Map<String, dynamic>? bodyEnviado;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final r = request as http.Request;
    bodyEnviado = json.decode(r.body) as Map<String, dynamic>;
    return http.StreamedResponse(
      Stream.value(utf8.encode(json.encode({
        'respuesta': 'Veo las imágenes.',
        'tools_usadas': <String>[],
        'tablas_cambiadas': <String>[],
      }))),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

void main() {
  test('adjunta UNA imagen como lista `imagenes` en el body', () async {
    final fake = _FakeClient();
    final repo = MatixChatRepository(MatixClient(inner: fake));
    const dataUrl = 'data:image/jpeg;base64,/9j/4AAQ==';

    final turno = await repo.enviar(
      historial: const <Mensaje>[],
      mensaje: 'mira esto',
      imagenes: const [dataUrl],
    );

    expect(turno.respuesta, 'Veo las imágenes.');
    expect(fake.bodyEnviado!['mensaje'], 'mira esto');
    expect(fake.bodyEnviado!['imagenes'], const [dataUrl]);
  });

  test('adjunta VARIAS imágenes en el body', () async {
    final fake = _FakeClient();
    final repo = MatixChatRepository(MatixClient(inner: fake));
    const a = 'data:image/jpeg;base64,AAAA';
    const b = 'data:image/jpeg;base64,BBBB';

    await repo.enviar(
      historial: const <Mensaje>[],
      mensaje: 'mira estas',
      imagenes: const [a, b],
    );

    final imgs = fake.bodyEnviado!['imagenes'] as List;
    expect(imgs, hasLength(2));
    expect(imgs, containsAll(const [a, b]));
  });

  test('sin imágenes, el body NO incluye la clave `imagenes`', () async {
    final fake = _FakeClient();
    final repo = MatixChatRepository(MatixClient(inner: fake));

    await repo.enviar(historial: const <Mensaje>[], mensaje: 'hola');

    expect(fake.bodyEnviado!.containsKey('imagenes'), isFalse);
  });
}
