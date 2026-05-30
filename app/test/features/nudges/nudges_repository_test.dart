// Test del NudgesRepository (Push Capa 3b): que `obtener` mapee la
// config del cerebro y que `actualizar` arme el body con snake_case y
// solo los campos dados (PATCH parcial).

import 'package:flutter_test/flutter_test.dart';
import 'package:matix/api/matix_client.dart';
import 'package:matix/features/nudges/data/nudges_repository.dart';

class _FakeClient implements MatixClient {
  Map<String, dynamic>? ultimoPatch;
  String? ultimoPatchPath;

  @override
  Future<Map<String, dynamic>> getOne(String path) async => {
        'activo': true,
        'silencio_inicio': 23,
        'silencio_fin': 7,
      };

  @override
  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    ultimoPatchPath = path;
    ultimoPatch = body;
    return {'ok': true};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('obtener mapea la config del cerebro', () async {
    final repo = NudgesRepository(_FakeClient());
    final cfg = await repo.obtener();
    expect(cfg, isNotNull);
    expect(cfg!.activo, isTrue);
    expect(cfg.silencioInicio, 23);
    expect(cfg.silencioFin, 7);
  });

  test('actualizar manda solo los campos dados, en snake_case', () async {
    final fake = _FakeClient();
    final repo = NudgesRepository(fake);

    await repo.actualizar(activo: false);
    expect(fake.ultimoPatchPath, '/api/v1/nudges');
    expect(fake.ultimoPatch, {'activo': false});

    await repo.actualizar(silencioInicio: 22, silencioFin: 8);
    expect(fake.ultimoPatch, {'silencio_inicio': 22, 'silencio_fin': 8});
  });

  test('actualizar con disponibilidad la pasa bajo la clave correcta',
      () async {
    final fake = _FakeClient();
    final repo = NudgesRepository(fake);

    final disp = {
      for (var w = 1; w <= 7; w++)
        '$w': {'activo': true, 'inicio': 8, 'fin': 22},
    };
    await repo.actualizar(disponibilidad: disp);
    expect(fake.ultimoPatch, {'disponibilidad': disp});
  });

  test('actualizar sin campos no llama a la red', () async {
    final fake = _FakeClient();
    final repo = NudgesRepository(fake);

    await repo.actualizar();
    expect(fake.ultimoPatch, isNull);
  });
}
