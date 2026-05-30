import 'package:flutter_test/flutter_test.dart';
import 'package:matix/api/matix_client.dart';
import 'package:matix/features/finanzas/data/movimientos_repository.dart';
import 'package:matix/features/finanzas/domain/movimiento.dart';

/// Tests del CRUD del repo de movimientos sin red: un `MatixClient` falso
/// captura las llamadas (path + body) y devuelve filas canónicas, para
/// comprobar que el repo arma bien las peticiones y parsea la respuesta.

class _FakeClient implements MatixClient {
  final List<String> calls = [];
  String? lastPath;
  Map<String, dynamic>? lastBody;

  Map<String, dynamic> _fila({
    String id = 'm1',
    String tipo = 'gasto',
    double monto = 42.5,
    String categoria = 'Comida',
    String fecha = '2026-05-10',
    String nota = '',
  }) =>
      {
        'id': id,
        'tipo': tipo,
        'monto': monto,
        'categoria': categoria,
        'fecha': fecha,
        'nota': nota,
        'creado_en': '2026-05-10T12:00:00Z',
        'actualizado_en': '2026-05-10T12:00:00Z',
      };

  @override
  Future<List<dynamic>> getList(String path) async {
    calls.add('GET $path');
    return [
      _fila(id: 'a', tipo: 'ingreso', monto: 1000, categoria: 'Sueldo'),
      _fila(id: 'b', tipo: 'gasto', monto: 20, categoria: 'Comida'),
    ];
  }

  @override
  Future<Map<String, dynamic>> getOne(String path) async {
    calls.add('GET $path');
    return _fila();
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    calls.add('POST $path');
    lastPath = path;
    lastBody = body;
    return _fila(
      tipo: body['tipo'] as String,
      monto: (body['monto'] as num).toDouble(),
      categoria: body['categoria'] as String,
      fecha: body['fecha'] as String,
      nota: body['nota'] as String? ?? '',
    );
  }

  @override
  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    calls.add('PATCH $path');
    lastPath = path;
    lastBody = body;
    return _fila(
      tipo: body['tipo'] as String,
      monto: (body['monto'] as num).toDouble(),
      categoria: body['categoria'] as String,
      fecha: body['fecha'] as String,
      nota: body['nota'] as String? ?? '',
    );
  }

  @override
  Future<void> delete(String path) async {
    calls.add('DELETE $path');
    lastPath = path;
  }

  @override
  Future<Map<String, dynamic>> health() => throw UnimplementedError();

  @override
  void close() {}
}

void main() {
  test('listar parsea la lista de movimientos', () async {
    final repo = MovimientosRepository(_FakeClient());
    final lista = await repo.listar();
    expect(lista.length, 2);
    expect(lista[0].tipo, TipoMovimiento.ingreso);
    expect(lista[0].monto, 1000);
    expect(lista[1].categoria, 'Comida');
  });

  test('crear manda tipo/monto/categoria/fecha (yyyy-MM-dd) y parsea', () async {
    final fake = _FakeClient();
    final repo = MovimientosRepository(fake);
    final m = await repo.crear(
      tipo: TipoMovimiento.gasto,
      monto: 42.5,
      categoria: 'Comida',
      fecha: DateTime(2026, 5, 10),
      nota: 'almuerzo',
    );
    expect(fake.lastPath, '/api/v1/movimientos');
    expect(fake.lastBody!['tipo'], 'gasto');
    expect(fake.lastBody!['monto'], 42.5);
    expect(fake.lastBody!['categoria'], 'Comida');
    expect(fake.lastBody!['fecha'], '2026-05-10');
    expect(fake.lastBody!['nota'], 'almuerzo');
    expect(m.tipo, TipoMovimiento.gasto);
    expect(m.monto, 42.5);
  });

  test('actualizar usa PATCH con el id en el path', () async {
    final fake = _FakeClient();
    final repo = MovimientosRepository(fake);
    await repo.actualizar(
      id: 'm1',
      tipo: TipoMovimiento.ingreso,
      monto: 99,
      categoria: 'Sueldo',
      fecha: DateTime(2026, 6, 1),
    );
    expect(fake.lastPath, '/api/v1/movimientos/m1');
    expect(fake.calls.any((c) => c.startsWith('PATCH')), isTrue);
    expect(fake.lastBody!['tipo'], 'ingreso');
    expect(fake.lastBody!['fecha'], '2026-06-01');
  });

  test('borrar usa DELETE con el id en el path', () async {
    final fake = _FakeClient();
    final repo = MovimientosRepository(fake);
    await repo.borrar('m1');
    expect(fake.lastPath, '/api/v1/movimientos/m1');
    expect(fake.calls, contains('DELETE /api/v1/movimientos/m1'));
  });
}
