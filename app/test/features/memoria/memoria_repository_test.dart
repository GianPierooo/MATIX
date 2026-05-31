import 'package:flutter_test/flutter_test.dart';
import 'package:matix/api/matix_client.dart';
import 'package:matix/features/memoria/data/memoria_repository.dart';

/// Tests del repo de memoria personal: parseo de `Recuerdo` y que el body
/// del POST lleve los campos correctos (incluida `esencial`).

class _FakeClient implements MatixClient {
  Map<String, dynamic>? ultimoPost;
  String? ultimoDeletePath;

  @override
  Future<List<dynamic>> getList(String path) async => [
        {
          'id': 'a1',
          'contenido': 'Mi meta es aprobar Cálculo',
          'categoria': 'metas',
          'esencial': true,
        },
        {
          'id': 'a2',
          'contenido': 'Detalle largo',
          'categoria': null,
          'esencial': false,
        },
      ];

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    ultimoPost = body;
    return {
      'id': 'nuevo',
      'contenido': body['contenido'],
      'categoria': body['categoria'],
      'esencial': body['esencial'] ?? true,
    };
  }

  @override
  Future<void> delete(String path) async {
    ultimoDeletePath = path;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Recuerdo.fromJson parsea campos + esencial', () {
    final r = Recuerdo.fromJson({
      'id': 'x',
      'contenido': 'algo',
      'categoria': 'metas',
      'esencial': false,
    });
    expect(r.id, 'x');
    expect(r.contenido, 'algo');
    expect(r.categoria, 'metas');
    expect(r.esencial, isFalse);
  });

  test('listar mapea la respuesta del cerebro', () async {
    final repo = MemoriaRepository(_FakeClient());
    final lista = await repo.listar();
    expect(lista.length, 2);
    expect(lista.first.contenido, 'Mi meta es aprobar Cálculo');
    expect(lista[1].esencial, isFalse);
    expect(lista[1].categoria, isNull);
  });

  test('crear manda contenido + categoria + esencial', () async {
    final fake = _FakeClient();
    final repo = MemoriaRepository(fake);
    await repo.crear(
      contenido: 'Tengo un perro, Toby',
      categoria: 'personas',
      esencial: true,
    );
    expect(fake.ultimoPost, {
      'contenido': 'Tengo un perro, Toby',
      'categoria': 'personas',
      'esencial': true,
    });
  });

  test('crear sin categoría no la incluye en el body', () async {
    final fake = _FakeClient();
    final repo = MemoriaRepository(fake);
    await repo.crear(contenido: 'algo suelto', esencial: false);
    expect(fake.ultimoPost!.containsKey('categoria'), isFalse);
    expect(fake.ultimoPost!['esencial'], isFalse);
  });

  test('borrar pega al endpoint del id', () async {
    final fake = _FakeClient();
    final repo = MemoriaRepository(fake);
    await repo.borrar('a1');
    expect(fake.ultimoDeletePath, '/api/v1/memoria/a1');
  });
}
