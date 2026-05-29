import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/core/notificaciones_service.dart';
import 'package:matix/features/briefing/data/briefing_prefs.dart';
import 'package:matix/features/briefing/providers/briefing_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests del `BriefingConfigController` (Capa 8 reducida · Paso 1).
///
/// Lo importante: cuando el usuario activa el briefing y/o cambia la
/// hora, el controller persiste en SharedPreferences y le pide a
/// `NotificacionesService` que programe/cancele con el id estable.
/// No tocamos `flutter_local_notifications` real — pasamos un servicio
/// fake que registra las llamadas.

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
    // SharedPreferences mockeado para que el controller pueda persistir.
    SharedPreferences.setMockInitialValues({});
  });

  ProviderContainer containerCon(_NotisFake fake) => ProviderContainer(
        overrides: [
          notificacionesServiceProvider.overrideWithValue(fake),
        ],
      );

  test('estado inicial: opt-in off, hora 08:00', () async {
    final fake = _NotisFake();
    final c = containerCon(fake);
    addTearDown(c.dispose);
    // Forzamos primer read para que el controller corra `_cargar`.
    await c.read(briefingConfigProvider.notifier).ready;
    final cfg = c.read(briefingConfigProvider);
    expect(cfg.activo, isFalse);
    expect(cfg.hora, BriefingPrefs.horaDefault);
    expect(cfg.minuto, BriefingPrefs.minutoDefault);
  });

  test('activar(true) pide permisos y programa con payload=briefing',
      () async {
    final fake = _NotisFake();
    final c = containerCon(fake);
    addTearDown(c.dispose);
    await c.read(briefingConfigProvider.notifier).ready;

    await c.read(briefingConfigProvider.notifier).activar(true);

    expect(fake.permisos, 1);
    expect(fake.programadas, hasLength(1));
    final p = fake.programadas.single;
    expect(p.id, BriefingPrefs.idNotificacion);
    expect(p.hora, BriefingPrefs.horaDefault);
    expect(p.minuto, BriefingPrefs.minutoDefault);
    expect(p.payload, 'briefing');
    expect(c.read(briefingConfigProvider).activo, isTrue);
  });

  test('activar(false) cancela', () async {
    final fake = _NotisFake();
    final c = containerCon(fake);
    addTearDown(c.dispose);
    c.read(briefingConfigProvider);
    await c.read(briefingConfigProvider.notifier).activar(true);

    await c.read(briefingConfigProvider.notifier).activar(false);

    expect(fake.canceladas, [BriefingPrefs.idNotificacion]);
    expect(c.read(briefingConfigProvider).activo, isFalse);
  });

  test(
    'cambiarHora estando activo reprograma con el nuevo horario',
    () async {
      final fake = _NotisFake();
      final c = containerCon(fake);
      addTearDown(c.dispose);
      c.read(briefingConfigProvider);
      await c.read(briefingConfigProvider.notifier).activar(true);
      fake.programadas.clear();

      await c.read(briefingConfigProvider.notifier).cambiarHora(7, 15);

      expect(fake.programadas, hasLength(1));
      expect(fake.programadas.single.hora, 7);
      expect(fake.programadas.single.minuto, 15);
      // El estado refleja el cambio y se persistió.
      final cfg = c.read(briefingConfigProvider);
      expect(cfg.hora, 7);
      expect(cfg.minuto, 15);
    },
  );

  test(
    'cambiarHora estando desactivado solo persiste, NO programa',
    () async {
      final fake = _NotisFake();
      final c = containerCon(fake);
      addTearDown(c.dispose);
      c.read(briefingConfigProvider);

      await c.read(briefingConfigProvider.notifier).cambiarHora(6, 30);

      expect(fake.programadas, isEmpty);
      expect(c.read(briefingConfigProvider).hora, 6);
      expect(c.read(briefingConfigProvider).minuto, 30);
    },
  );

  test('persistencia: tras guardar, un container nuevo recupera valores',
      () async {
    final fake1 = _NotisFake();
    final c1 = containerCon(fake1);
    await c1.read(briefingConfigProvider.notifier).ready;
    await c1.read(briefingConfigProvider.notifier).cambiarHora(9, 45);
    await c1.read(briefingConfigProvider.notifier).activar(true);
    c1.dispose();

    final fake2 = _NotisFake();
    final c2 = containerCon(fake2);
    addTearDown(c2.dispose);
    await c2.read(briefingConfigProvider.notifier).ready;
    final cfg = c2.read(briefingConfigProvider);
    expect(cfg.activo, isTrue);
    expect(cfg.hora, 9);
    expect(cfg.minuto, 45);
    // Y como quedó activo, el nuevo container reprograma al arrancar.
    expect(fake2.programadas, hasLength(1));
  });
}
