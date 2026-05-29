import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/core/notificaciones_service.dart';
import 'package:matix/features/cierre/data/cierre_prefs.dart';
import 'package:matix/features/cierre/providers/cierre_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests del `CierreConfigController` (Capa 8 · Paso 2). Mismo
/// contrato que el del briefing: activar pide permisos + programa
/// con su id/payload; desactivar cancela; cambiar hora reprograma;
/// persiste entre sesiones. Default: opt-in off, 21:00.

class _NotisFake extends NotificacionesService {
  final List<({int id, int hora, int minuto, String? payload})> programadas =
      [];
  final List<int> canceladas = [];
  int permisos = 0;

  @override
  Future<void> inicializar() async {}

  @override
  Future<bool> pedirPermisos() async {
    permisos++;
    return true;
  }

  @override
  Future<void> programarDiaria({
    required int id,
    required String titulo,
    required String cuerpo,
    required int hora,
    required int minuto,
    String? payload,
  }) async {
    programadas.add(
      (id: id, hora: hora, minuto: minuto, payload: payload),
    );
  }

  @override
  Future<void> cancelar(int id) async {
    canceladas.add(id);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ProviderContainer containerCon(_NotisFake fake) => ProviderContainer(
        overrides: [
          notificacionesServiceProvider.overrideWithValue(fake),
        ],
      );

  test('estado inicial: opt-in off, hora 21:00', () async {
    final fake = _NotisFake();
    final c = containerCon(fake);
    addTearDown(c.dispose);
    await c.read(cierreConfigProvider.notifier).ready;
    final cfg = c.read(cierreConfigProvider);
    expect(cfg.activo, isFalse);
    expect(cfg.hora, CierrePrefs.horaDefault);
    expect(cfg.hora, 21);
    expect(cfg.minuto, 0);
  });

  test('activar(true) pide permisos y programa con payload=cierre',
      () async {
    final fake = _NotisFake();
    final c = containerCon(fake);
    addTearDown(c.dispose);
    await c.read(cierreConfigProvider.notifier).ready;

    await c.read(cierreConfigProvider.notifier).activar(true);

    expect(fake.permisos, 1);
    expect(fake.programadas, hasLength(1));
    final p = fake.programadas.single;
    expect(p.id, CierrePrefs.idNotificacion);
    expect(p.hora, 21);
    expect(p.payload, 'cierre');
    expect(c.read(cierreConfigProvider).activo, isTrue);
  });

  test('id del cierre distinto del briefing', () {
    // Garantiza que no se pisan las dos notificaciones diarias.
    expect(CierrePrefs.idNotificacion, isNot(8000001));
  });

  test('activar(false) cancela', () async {
    final fake = _NotisFake();
    final c = containerCon(fake);
    addTearDown(c.dispose);
    await c.read(cierreConfigProvider.notifier).ready;
    await c.read(cierreConfigProvider.notifier).activar(true);

    await c.read(cierreConfigProvider.notifier).activar(false);

    expect(fake.canceladas, [CierrePrefs.idNotificacion]);
    expect(c.read(cierreConfigProvider).activo, isFalse);
  });

  test('cambiarHora estando activo reprograma', () async {
    final fake = _NotisFake();
    final c = containerCon(fake);
    addTearDown(c.dispose);
    await c.read(cierreConfigProvider.notifier).ready;
    await c.read(cierreConfigProvider.notifier).activar(true);
    fake.programadas.clear();

    await c.read(cierreConfigProvider.notifier).cambiarHora(22, 30);

    expect(fake.programadas, hasLength(1));
    expect(fake.programadas.single.hora, 22);
    expect(fake.programadas.single.minuto, 30);
    final cfg = c.read(cierreConfigProvider);
    expect(cfg.hora, 22);
    expect(cfg.minuto, 30);
  });

  test('persistencia entre containers', () async {
    final fake1 = _NotisFake();
    final c1 = containerCon(fake1);
    await c1.read(cierreConfigProvider.notifier).ready;
    await c1.read(cierreConfigProvider.notifier).cambiarHora(20, 15);
    await c1.read(cierreConfigProvider.notifier).activar(true);
    c1.dispose();

    final fake2 = _NotisFake();
    final c2 = containerCon(fake2);
    addTearDown(c2.dispose);
    await c2.read(cierreConfigProvider.notifier).ready;
    final cfg = c2.read(cierreConfigProvider);
    expect(cfg.activo, isTrue);
    expect(cfg.hora, 20);
    expect(cfg.minuto, 15);
    expect(fake2.programadas, hasLength(1));
  });
}
