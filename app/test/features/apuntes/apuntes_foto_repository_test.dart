import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matix/api/matix_client.dart';
import 'package:matix/features/apuntes/data/apuntes_foto_repository.dart';

/// Tests del `ApuntesFotoRepository` — la capa que arma el multipart
/// para el endpoint `POST /api/v1/apuntes/desde-foto` (Capa 7 · Paso 1).
///
/// No tocamos red real: pasamos un cliente HTTP fake que captura la
/// `MultipartRequest` para inspeccionarla. Tampoco hace falta una foto
/// real — escribimos unos bytes a un temporal.

class _FakeClient extends http.BaseClient {
  _FakeClient({required this.respuesta});

  final http.Response respuesta;
  http.BaseRequest? capturado;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    capturado = request;
    // El request es multipart → finalize() escupe los bytes del body.
    // No los inspeccionamos acá; el test verifica los `fields` y
    // `files` directamente sobre la request capturada.
    await request.finalize().toBytes();
    return http.StreamedResponse(
      Stream.value(utf8.encode(respuesta.body)),
      respuesta.statusCode,
      // Sin `Content-Type: ...; charset=utf-8`, el cliente decodea
      // como latin-1 y los acentos se rompen ("é" → "Ã©").
      headers: {
        'content-type': 'application/json; charset=utf-8',
        ...respuesta.headers,
      },
    );
  }
}

Map<String, dynamic> _apunteJson({
  required bool ocrOk,
  String? mensajeOcr,
  String contenido = 'Texto extraído.',
}) => {
      'id': '11111111-1111-1111-1111-111111111111',
      'titulo': '_test',
      'contenido': contenido,
      'cuaderno_id': null,
      'curso_id': null,
      'proyecto_id': null,
      'etiquetas': <String>[],
      'adjuntos': [
        {
          'url': 'https://fake/storage/x.jpg',
          'tipo': 'image/jpeg',
          'nombre': 'foto.jpg',
        },
      ],
      'eliminado_en': null,
      'creado_en': '2026-05-28T12:00:00+00:00',
      'actualizado_en': '2026-05-28T12:00:00+00:00',
      'ocr_ok': ocrOk,
      'mensaje_ocr': mensajeOcr,
    };

Future<File> _fotoTemp() async {
  // `Directory.systemTemp` viene del SDK de Dart y funciona en
  // flutter_test sin necesidad del plugin path_provider (que no
  // tiene impl en el entorno de tests).
  final dir = Directory.systemTemp.createTempSync('matix_test_');
  final f = File('${dir.path}/foto.jpg');
  await f.writeAsBytes([0xff, 0xd8, 0xff, 0xd9]); // JPEG SOI/EOI mínimo
  return f;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('subir() arma multipart con file + fields opcionales', () async {
    final fake = _FakeClient(
      respuesta: http.Response(json.encode(_apunteJson(ocrOk: true)), 201),
    );
    final repo = ApuntesFotoRepository(inner: fake);
    final foto = await _fotoTemp();
    addTearDown(() => foto.deleteSync());

    await repo.subir(
      foto,
      titulo: '_test_titulo',
      cursoId: 'curso-uuid',
      etiquetas: ['a', 'b'],
    );

    final req = fake.capturado;
    expect(req, isNotNull);
    expect(req is http.MultipartRequest, isTrue);
    final mr = req! as http.MultipartRequest;
    expect(mr.url.path.endsWith('/api/v1/apuntes/desde-foto'), isTrue);
    expect(mr.fields['titulo'], '_test_titulo');
    expect(mr.fields['curso_id'], 'curso-uuid');
    expect(mr.fields['etiquetas'], 'a,b');
    // Sin proyecto/cuaderno → no aparecen como campos vacíos.
    expect(mr.fields.containsKey('proyecto_id'), isFalse);
    expect(mr.files, hasLength(1));
    expect(mr.files.first.field, 'file');
  });

  test('subir() parsea ocr_ok=true y mensaje_ocr null', () async {
    final fake = _FakeClient(
      respuesta: http.Response(
        json.encode(_apunteJson(ocrOk: true, contenido: 'Hola')),
        201,
      ),
    );
    final repo = ApuntesFotoRepository(inner: fake);
    final foto = await _fotoTemp();
    addTearDown(() => foto.deleteSync());

    final r = await repo.subir(foto);
    expect(r.ocrOk, isTrue);
    expect(r.mensajeOcr, isNull);
    expect(r.apunte.contenido, 'Hola');
  });

  test('subir() parsea ocr_ok=false y mensaje', () async {
    final fake = _FakeClient(
      respuesta: http.Response(
        json.encode(_apunteJson(
          ocrOk: false,
          mensajeOcr: 'No detecté texto legible.',
          contenido: '',
        )),
        201,
      ),
    );
    final repo = ApuntesFotoRepository(inner: fake);
    final foto = await _fotoTemp();
    addTearDown(() => foto.deleteSync());

    final r = await repo.subir(foto);
    expect(r.ocrOk, isFalse);
    expect(r.mensajeOcr, 'No detecté texto legible.');
    expect(r.apunte.contenido, '');
  });

  test('subir() lanza MatixApiException si el cerebro responde 4xx',
      () async {
    final fake = _FakeClient(
      respuesta: http.Response(
        json.encode({'detail': 'Imagen muy grande.'}),
        400,
      ),
    );
    final repo = ApuntesFotoRepository(inner: fake);
    final foto = await _fotoTemp();
    addTearDown(() => foto.deleteSync());

    await expectLater(
      repo.subir(foto),
      throwsA(isA<MatixApiException>().having(
        (e) => e.statusCode,
        'statusCode',
        400,
      )),
    );
  });
}
