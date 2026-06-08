import 'package:flutter_test/flutter_test.dart';
import 'package:matix/api/matix_client.dart';
import 'package:matix/core/notificaciones_service.dart';
import 'package:matix/features/horario/data/horario_repository.dart';
import 'package:matix/features/horario/data/notis_proactivas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests del servicio que toma la lista del cerebro y la programa LOCAL.
/// Cubre: idempotencia (mismo dedup_key → mismo ID), cancelación de los IDs
/// del refresh anterior, programación con el cliente real fakeado.

class _NotifFake implements NotificacionesService {
  final List<int> programados = [];
  final List<int> cancelados = [];
  bool programarRetorno = true;

  @override
  Future<bool> programar({
    required int id,
    required String titulo,
    required String cuerpo,
    required DateTime cuando,
    bool exacto = false,
    String? payload,
  }) async {
    if (programarRetorno) programados.add(id);
    return programarRetorno;
  }

  @override
  Future<void> cancelar(int id) async {
    cancelados.add(id);
  }

  // Resto de la interfaz: no se usa en este test, lanzar si se invoca por error.
  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '_NotifFake no implementa ${invocation.memberName}',
      );
}

class _RepoFake extends HorarioRepository {
  _RepoFake(this._respuesta) : super(_ClienteVacio());
  final Map<String, dynamic> _respuesta;

  @override
  Future<Map<String, dynamic>> traerNotisProgramadas() async => _respuesta;
}

/// Cliente vacío para satisfacer el constructor del repo; nunca se invoca.
class _ClienteVacio implements MatixClient {
  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_ClienteVacio no debería usarse en este test');
}

Map<String, dynamic> _noti({
  required String tipo,
  required String dedup,
  required DateTime cuando,
  String titulo = 't',
  String cuerpo = 'c',
  String payload = 'abrir_tu_dia',
}) {
  return {
    'tipo': tipo,
    'dedup_key': dedup,
    'disparar_en': cuando.toUtc().toIso8601String(),
    'titulo': titulo,
    'cuerpo': cuerpo,
    'payload': payload,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('idDe es estable y determinista por dedup_key', () {
    final a1 = NotisProactivasService.idDe('pre_actividad|2026-06-08|10:45|abc');
    final a2 = NotisProactivasService.idDe('pre_actividad|2026-06-08|10:45|abc');
    final b = NotisProactivasService.idDe('pre_actividad|2026-06-08|10:45|xyz');
    expect(a1, equals(a2));
    expect(a1, isNot(equals(b)));
    // En el rango reservado (offset 0x40000000): cabe en int 31-bit positivo.
    expect(a1, greaterThanOrEqualTo(0x40000000));
    expect(a1, lessThan(0x80000000));
  });

  test('refrescar() programa una noti por cada entrada del servidor', () async {
    final futuro = DateTime.now().add(const Duration(hours: 2));
    final repo = _RepoFake({
      'notis': [
        _noti(tipo: 'resumen_matutino', dedup: 'resumen_matutino|2026-06-08',
            cuando: futuro),
        _noti(tipo: 'pre_actividad',
            dedup: 'pre_actividad|2026-06-08|10:45|abc', cuando: futuro),
      ],
    });
    final notif = _NotifFake();
    final svc = NotisProactivasService(repo, notif);

    final r = await svc.refrescar();

    expect(r['programadas'], 2);
    expect(notif.programados.length, 2);
    // IDs distintos para dedup_keys distintos.
    expect(notif.programados.toSet().length, 2);
  });

  test('refrescar() cancela los IDs del refresh anterior antes de programar',
      () async {
    // Primera ronda: 2 notis del día de ayer.
    final ayer = DateTime.now().add(const Duration(hours: 1));
    final repo1 = _RepoFake({
      'notis': [
        _noti(tipo: 'pre_actividad',
            dedup: 'pre_actividad|2026-06-07|10:45|abc', cuando: ayer),
        _noti(tipo: 'pre_actividad',
            dedup: 'pre_actividad|2026-06-07|17:30|xyz', cuando: ayer),
      ],
    });
    final notif = _NotifFake();
    await NotisProactivasService(repo1, notif).refrescar();
    expect(notif.programados.length, 2);
    final viejosIds = List<int>.from(notif.programados);

    // Segunda ronda: 1 noti del día NUEVO. Las 2 del día anterior deben
    // cancelarse para no quedar colgando en el scheduler.
    final hoy = DateTime.now().add(const Duration(hours: 3));
    final repo2 = _RepoFake({
      'notis': [
        _noti(tipo: 'resumen_matutino', dedup: 'resumen_matutino|2026-06-08',
            cuando: hoy),
      ],
    });
    await NotisProactivasService(repo2, notif).refrescar();

    expect(notif.cancelados, containsAll(viejosIds));
    expect(notif.programados.length, 3); // 2 viejos + 1 nuevo
  });

  test('refrescar() es idempotente con el mismo input: misma cantidad de IDs',
      () async {
    final cuando = DateTime.now().add(const Duration(hours: 2));
    final notis = [
      _noti(tipo: 'pre_actividad',
          dedup: 'pre_actividad|2026-06-08|10:45|abc', cuando: cuando),
    ];
    final repo = _RepoFake({'notis': notis});
    final notif = _NotifFake();
    final svc = NotisProactivasService(repo, notif);

    await svc.refrescar();
    final tras1 = List<int>.from(notif.programados);
    await svc.refrescar();
    // El segundo refresco cancela el del primero (mismo ID, dedup estable) y
    // re-programa: la cuenta TOTAL en el log de fake es 2 (cada refrescar
    // llama a programar), pero el ID es EL MISMO — el plugin sustituye, no
    // duplica. Esto se valida con el id estable.
    expect(notif.programados.length, 2);
    expect(notif.programados[0], equals(notif.programados[1]));
    expect(notif.cancelados, contains(tras1.first));
  });

  test('refrescar() tolera fallo de red sin crashear', () async {
    final repoQueExplota = _RepoErrante();
    final notif = _NotifFake();
    final svc = NotisProactivasService(repoQueExplota, notif);

    final r = await svc.refrescar();
    expect(r['programadas'], 0);
    expect(notif.programados, isEmpty);
  });

  test('refrescar() ignora notis con campos inválidos (defensivo)', () async {
    final cuando = DateTime.now().add(const Duration(hours: 2));
    final repo = _RepoFake({
      'notis': [
        {'dedup_key': '', 'disparar_en': cuando.toIso8601String()}, // sin dedup
        {'dedup_key': 'x|y', 'disparar_en': 'fecha-invalida'},      // ISO mal
        _noti(tipo: 'pre_actividad', dedup: 'pre_actividad|x|y|z', cuando: cuando),
      ],
    });
    final notif = _NotifFake();
    final svc = NotisProactivasService(repo, notif);
    final r = await svc.refrescar();
    expect(r['programadas'], 1);
    expect(notif.programados.length, 1);
  });
}

class _RepoErrante extends HorarioRepository {
  _RepoErrante() : super(_ClienteVacio());
  @override
  Future<Map<String, dynamic>> traerNotisProgramadas() async {
    throw const SocketExceptionFake();
  }
}

class SocketExceptionFake implements Exception {
  const SocketExceptionFake();
  @override
  String toString() => 'simulated network failure';
}
