import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/wakeword/data/wakeword_crumbs.dart';
import 'package:matix/features/wakeword/data/wakeword_service.dart';
import 'package:matix/features/wakeword/providers/wakeword_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake del escuchador: cuenta arranques/paradas y guarda el callback de
/// detección para dispararlo a mano.
class _FakeEscucha implements WakeWordEscucha {
  int iniciarCount = 0;
  int detenerCount = 0;
  bool _activo = false;
  void Function()? _onDeteccion;

  @override
  bool get activo => _activo;

  @override
  Future<void> iniciar({
    required double umbral,
    required void Function() onDeteccion,
  }) async {
    iniciarCount++;
    _activo = true;
    _onDeteccion = onDeteccion;
  }

  @override
  Future<void> detener() async {
    detenerCount++;
    _activo = false;
  }

  @override
  Future<void> liberar() async {}

  void simularDeteccion() => _onDeteccion?.call();
}

/// Fake que SIEMPRE falla al iniciar (simula carga ONNX rota en el device).
class _EscuchaQueFalla implements WakeWordEscucha {
  int detenerCount = 0;
  @override
  bool get activo => false;
  @override
  Future<void> iniciar({
    required double umbral,
    required void Function() onDeteccion,
  }) async {
    throw Exception('ONNX no cargó (simulado)');
  }

  @override
  Future<void> detener() async => detenerCount++;
  @override
  Future<void> liberar() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer hacerContainer(_FakeEscucha fake) {
    final c = ProviderContainer(overrides: [
      wakeWordServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('con la palabra activa, al frente arranca la escucha', () async {
    SharedPreferences.setMockInitialValues({'wakeword_activo': true});
    final fake = _FakeEscucha();
    final c = hacerContainer(fake);
    final ctrl = c.read(wakeWordControllerProvider.notifier);

    await ctrl.alFrente();

    expect(fake.iniciarCount, 1);
    expect(c.read(wakeWordControllerProvider).fase, FaseWakeWord.escuchando);
  });

  test('con la palabra apagada, al frente NO arranca', () async {
    SharedPreferences.setMockInitialValues({'wakeword_activo': false});
    final fake = _FakeEscucha();
    final c = hacerContainer(fake);
    await c.read(wakeWordControllerProvider.notifier).alFrente();
    expect(fake.iniciarCount, 0);
    expect(c.read(wakeWordControllerProvider).fase, FaseWakeWord.desactivado);
  });

  test('relevo de micro: pausa con manos libres y retoma al terminar',
      () async {
    SharedPreferences.setMockInitialValues({'wakeword_activo': true});
    final fake = _FakeEscucha();
    final c = hacerContainer(fake);
    final ctrl = c.read(wakeWordControllerProvider.notifier);

    await ctrl.alFrente(); // escuchando
    expect(fake.iniciarCount, 1);

    ctrl.pausarPorVoz(); // manos libres toma el micro
    expect(fake.detenerCount, greaterThanOrEqualTo(1));
    expect(c.read(wakeWordControllerProvider).fase, FaseWakeWord.pausadoPorVoz);

    await ctrl.reanudarTrasVoz(); // manos libres terminó
    expect(fake.iniciarCount, 2); // retomó la escucha
    expect(c.read(wakeWordControllerProvider).fase, FaseWakeWord.escuchando);
  });

  test('al fondo suelta el micro (v1 solo escucha con la app abierta)',
      () async {
    SharedPreferences.setMockInitialValues({'wakeword_activo': true});
    final fake = _FakeEscucha();
    final c = hacerContainer(fake);
    final ctrl = c.read(wakeWordControllerProvider.notifier);

    await ctrl.alFrente();
    await ctrl.alFondo();

    expect(fake.detenerCount, greaterThanOrEqualTo(1));
    expect(c.read(wakeWordControllerProvider).fase, FaseWakeWord.desactivado);
  });

  test('al detectar: suelta el micro y avisa para abrir manos libres',
      () async {
    SharedPreferences.setMockInitialValues({'wakeword_activo': true});
    final fake = _FakeEscucha();
    final c = hacerContainer(fake);
    final ctrl = c.read(wakeWordControllerProvider.notifier);

    var abierto = 0;
    ctrl.registrarAlDetectar(() => abierto++);
    await ctrl.alFrente();
    final detenerAntes = fake.detenerCount;

    fake.simularDeteccion();

    expect(abierto, 1); // disparó la navegación a manos libres
    expect(fake.detenerCount, greaterThan(detenerAntes)); // soltó el micro
    expect(c.read(wakeWordControllerProvider).fase, FaseWakeWord.pausadoPorVoz);
  });

  test('si iniciar falla (ONNX roto), va a estado error SIN crashear',
      () async {
    SharedPreferences.setMockInitialValues({'wakeword_activo': true});
    final fake = _EscuchaQueFalla();
    final c = ProviderContainer(overrides: [
      wakeWordServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);
    final ctrl = c.read(wakeWordControllerProvider.notifier);

    // No debe lanzar: el fallo se traduce a estado error, no a excepción.
    await ctrl.activar(true);

    expect(c.read(wakeWordControllerProvider).fase, FaseWakeWord.error);
    expect(c.read(wakeWordControllerProvider).error, isNotNull);
  });

  test('circuit breaker: si la última activación murió, NO auto-arranca y '
      'desarma (evita bucle de crashes)', () async {
    SharedPreferences.setMockInitialValues({'wakeword_activo': true});
    final tmp = await Directory.systemTemp.createTemp('ww_cb');
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });
    final crumbs = WakeWordCrumbs(archivo: File('${tmp.path}/c.txt'));
    await crumbs.preparar();
    crumbs.marca('sesion:mel'); // la vez pasada murió creando esa sesión

    final fake = _FakeEscucha();
    final c = ProviderContainer(overrides: [
      wakeWordServiceProvider.overrideWithValue(fake),
      wakeWordCrumbsProvider.overrideWithValue(crumbs),
    ]);
    addTearDown(c.dispose);
    final ctrl = c.read(wakeWordControllerProvider.notifier);

    await ctrl.alFrente(); // arranque de app: debería frenar, no reintentar

    expect(fake.iniciarCount, 0); // NO auto-arrancó
    expect(c.read(wakeWordControllerProvider).fase, FaseWakeWord.error);
    expect(c.read(wakeWordControllerProvider).error, contains('sesion:mel'));
    expect(await ctrl.estaActivo(), isFalse); // se desarmó solo
  });

  test('alFrente arranca normal si el último cierre fue limpio', () async {
    SharedPreferences.setMockInitialValues({'wakeword_activo': true});
    final tmp = await Directory.systemTemp.createTemp('ww_cb_ok');
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });
    final crumbs = WakeWordCrumbs(archivo: File('${tmp.path}/c.txt'));
    await crumbs.preparar();
    crumbs.marca('apagado'); // cierre limpio anterior

    final fake = _FakeEscucha();
    final c = ProviderContainer(overrides: [
      wakeWordServiceProvider.overrideWithValue(fake),
      wakeWordCrumbsProvider.overrideWithValue(crumbs),
    ]);
    addTearDown(c.dispose);

    await c.read(wakeWordControllerProvider.notifier).alFrente();

    expect(fake.iniciarCount, 1);
    expect(c.read(wakeWordControllerProvider).fase, FaseWakeWord.escuchando);
  });

  test('activar(true) persiste y arranca; activar(false) apaga', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = _FakeEscucha();
    final c = hacerContainer(fake);
    final ctrl = c.read(wakeWordControllerProvider.notifier);

    await ctrl.activar(true);
    expect(fake.iniciarCount, 1);
    expect(await ctrl.estaActivo(), isTrue);

    await ctrl.activar(false);
    expect(fake.detenerCount, greaterThanOrEqualTo(1));
    expect(await ctrl.estaActivo(), isFalse);
    expect(c.read(wakeWordControllerProvider).fase, FaseWakeWord.desactivado);
  });
}
