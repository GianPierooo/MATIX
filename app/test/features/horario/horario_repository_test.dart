import 'package:flutter_test/flutter_test.dart';
import 'package:matix/api/matix_client.dart';
import 'package:matix/features/horario/data/horario_repository.dart';
import 'package:matix/features/horario/domain/plan_dia.dart';

/// Cliente falso: registra a qué ruta y con qué cuerpo se llamó, sin red.
class _FakeClient extends MatixClient {
  final List<String> gets = [];
  final List<({String path, Map<String, dynamic> body})> posts = [];
  Map<String, dynamic> respGet = const {};
  Map<String, dynamic> respPost = const {};

  @override
  Future<Map<String, dynamic>> getOne(String path) async {
    gets.add(path);
    return respGet;
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    posts.add((path: path, body: body));
    return respPost;
  }
}

void main() {
  late _FakeClient client;
  late HorarioRepository repo;

  setUp(() {
    client = _FakeClient();
    repo = HorarioRepository(client);
  });

  test('cargar() pega a GET /horario y parsea el plan', () async {
    client.respGet = {
      'fecha': '2026-06-04',
      'despierta': '07:00',
      'duerme': '23:00',
      'bloques': [
        {'inicio': '08:00', 'fin': '09:30', 'titulo': 'OneXotic', 'tipo': 'trabajo', 'tentativo': true},
      ],
      'fuera': const [],
    };
    final plan = await repo.cargar();
    expect(client.gets, ['/api/v1/horario']);
    expect(plan, isA<PlanDia>());
    expect(plan.bloques.single.titulo, 'OneXotic');
  });

  test('cargar(desdeAhora) pega a POST /replanificar', () async {
    client.respPost = {
      'fecha': '2026-06-04', 'despierta': '07:00', 'duerme': '23:00',
      'desde': '16:30', 'bloques': const [], 'fuera': const [],
    };
    final plan = await repo.cargar(desdeAhora: true);
    expect(client.posts.single.path, '/api/v1/horario/replanificar');
    expect(plan.esReplan, isTrue);
  });

  test('completar manda tarea_id/nodo_id', () async {
    await repo.completar(tareaId: 't1', nodoId: 'n1');
    final p = client.posts.single;
    expect(p.path, '/api/v1/horario/bloque/completar');
    expect(p.body, {'tarea_id': 't1', 'nodo_id': 'n1'});
  });

  test('saltar manda set_item_id', () async {
    await repo.saltar('s1');
    final p = client.posts.single;
    expect(p.path, '/api/v1/horario/bloque/saltar');
    expect(p.body, {'set_item_id': 's1'});
  });

  test('agendar manda título/horas + ids para enganchar al modelo Tarea↔bloque',
      () async {
    client.respPost = {'agendadas': 1, 'omitidas': 0, 'fecha': '2026-06-04'};
    final bloques = [
      const BloquePlan(
        inicio: '08:00', fin: '09:30', titulo: 'OneXotic',
        tipo: 'trabajo', tentativo: true, nodoId: 'n1', setItemId: 's1',
      ),
    ];
    final r = await repo.agendar(bloques);
    final p = client.posts.single;
    // Camino canónico de TAREA (no eventos): endpoint /agendar con los ids.
    expect(p.path, '/api/v1/horario/agendar');
    expect(p.body, {
      'bloques': [
        {
          'titulo': 'OneXotic',
          'inicio': '08:00',
          'fin': '09:30',
          'tipo': 'trabajo',
          'nodo_id': 'n1',
          'set_item_id': 's1',
        },
      ],
    });
    expect(r['agendadas'], 1);
  });
}
