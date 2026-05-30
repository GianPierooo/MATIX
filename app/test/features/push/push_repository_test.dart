import 'package:flutter_test/flutter_test.dart';
import 'package:matix/api/matix_client.dart';
import 'package:matix/features/push/data/push_repository.dart';

/// Tests del repo de push (FCM · Capa 1): que registrar el token y el push
/// de prueba peguen al endpoint correcto con el cuerpo correcto. Sin red:
/// un MatixClient falso captura las llamadas.

class _FakeClient implements MatixClient {
  String? lastPath;
  Map<String, dynamic>? lastBody;

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    lastPath = path;
    lastBody = body;
    if (path.endsWith('/probar')) {
      return {'enviados': 1, 'fallidos': 0, 'detalle': const ['ok:abc']};
    }
    return const {'ok': true};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('registrarToken postea token + plataforma al endpoint', () async {
    final fake = _FakeClient();
    final repo = PushRepository(fake);

    await repo.registrarToken('tok-123');

    expect(fake.lastPath, '/api/v1/push/registrar-token');
    expect(fake.lastBody!['token'], 'tok-123');
    expect(fake.lastBody!['plataforma'], 'android');
  });

  test('probar postea a /push/probar y devuelve el resumen', () async {
    final fake = _FakeClient();
    final repo = PushRepository(fake);

    final res = await repo.probar();

    expect(fake.lastPath, '/api/v1/push/probar');
    expect(res['enviados'], 1);
    expect(res['fallidos'], 0);
  });
}
