import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/api/matix_client.dart';
import 'package:matix/core/notificaciones_service.dart';
import 'package:matix/features/eventos/data/eventos_repository.dart';

/// Regresión del crash al CREAR un evento con recordatorio: el repo
/// cancela/programa sus notificaciones. Si el plugin revienta (caía con
/// "Missing type parameter." en la build minificada), crear/actualizar
/// NO deben propagar: el evento se guarda igual.

class _NotifQueRevienta implements NotificacionesService {
  int cancelarLlamadas = 0;
  int programarLlamadas = 0;

  PlatformException _boom() => PlatformException(
        code: 'error',
        message: 'Missing type parameter.',
      );

  @override
  Future<void> cancelar(int id) async {
    cancelarLlamadas++;
    throw _boom();
  }

  @override
  Future<bool> programar({
    required int id,
    required String titulo,
    required String cuerpo,
    required DateTime cuando,
    bool exacto = false,
    String? payload,
  }) async {
    programarLlamadas++;
    throw _boom();
  }

  @override
  Future<bool> pedirPermisos() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements MatixClient {
  Map<String, dynamic> _evento({String id = 'e1', String titulo = 'Examen'}) => {
        'id': id,
        'titulo': titulo,
        'inicia_en': '2026-06-01T14:00:00Z',
        'todo_el_dia': false,
        'recordar_en': '2026-06-01T13:00:00Z',
        'recordatorio_offset_min': 60,
        'origen': 'manual',
        'creado_en': '2026-05-30T10:00:00Z',
        'actualizado_en': '2026-05-30T10:00:00Z',
      };

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async =>
      _evento(titulo: body['titulo'] as String? ?? 'Evento');

  @override
  Future<Map<String, dynamic>> patch(
          String path, Map<String, dynamic> body) async =>
      _evento();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('crear un evento con recordatorio no crashea aunque las notifs revienten',
      () async {
    final notif = _NotifQueRevienta();
    final repo = EventosRepository(_FakeClient(), notif);

    final e = await repo.crear(
      titulo: 'Examen final',
      iniciaEn: DateTime.utc(2026, 6, 1, 14),
      recordatorioOffsetMin: 60,
    );

    // El evento se guardó pese a que cancelar/programar lanzaron.
    expect(e.titulo, isNotEmpty);
    expect(notif.cancelarLlamadas, greaterThan(0)); // se intentó, y se tragó
  });

  test('actualizar tampoco crashea aunque las notifs revienten', () async {
    final notif = _NotifQueRevienta();
    final repo = EventosRepository(_FakeClient(), notif);

    final e = await repo.actualizar('e1', {'titulo': 'Examen movido'});
    expect(e.id, isNotEmpty);
  });
}
