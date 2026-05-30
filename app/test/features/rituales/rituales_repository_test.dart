import 'package:flutter_test/flutter_test.dart';
import 'package:matix/api/matix_client.dart';
import 'package:matix/features/rituales/data/rituales_repository.dart';

/// Tests del repo de config de rituales (Push Capa 3a): que lea la config
/// del cerebro y que el cambio pegue al endpoint correcto. Sin red.

class _FakeClient implements MatixClient {
  String? lastPath;
  Map<String, dynamic>? lastBody;

  @override
  Future<List<dynamic>> getList(String path) async {
    return [
      {'ritual': 'briefing', 'activo': true, 'hora': 8, 'minuto': 0},
      {'ritual': 'cierre', 'activo': false, 'hora': 22, 'minuto': 30},
    ];
  }

  @override
  Future<Map<String, dynamic>> patch(
      String path, Map<String, dynamic> body) async {
    lastPath = path;
    lastBody = body;
    return const {'ok': true};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('obtener devuelve la config del ritual pedido', () async {
    final repo = RitualesRepository(_FakeClient());
    final b = await repo.obtener('briefing');
    expect(b, isNotNull);
    expect(b!.activo, isTrue);
    expect(b.hora, 8);
    expect(b.minuto, 0);

    final c = await repo.obtener('cierre');
    expect(c!.activo, isFalse);
    expect(c.hora, 22);
    expect(c.minuto, 30);
  });

  test('obtener devuelve null si el ritual no está', () async {
    final repo = RitualesRepository(_FakeClient());
    expect(await repo.obtener('inexistente'), isNull);
  });

  test('actualizar hace PATCH al endpoint del ritual con el cuerpo', () async {
    final fake = _FakeClient();
    final repo = RitualesRepository(fake);
    await repo.actualizar('cierre', activo: true, hora: 21, minuto: 15);
    expect(fake.lastPath, '/api/v1/rituales/cierre');
    expect(fake.lastBody, {'activo': true, 'hora': 21, 'minuto': 15});
  });
}
