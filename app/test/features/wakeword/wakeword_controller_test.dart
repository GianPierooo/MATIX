import 'dart:io';

import 'package:flutter/services.dart';
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
  void Function(double)? _onScore;

  @override
  bool get activo => _activo;

  @override
  Future<void> iniciar({
    required double umbral,
    required void Function() onDeteccion,
    void Function(double score)? onScore,
  }) async {
    iniciarCount++;
    _activo = true;
    _onDeteccion = onDeteccion;
    _onScore = onScore;
  }

  double? umbralFijado;
  @override
  void fijarUmbral(double umbral) => umbralFijado = umbral;

  @override
  Future<void> detener() async {
    detenerCount++;
    _activo = false;
  }

  @override
  Future<void> liberar() async {}

  void simularDeteccion() => _onDeteccion?.call();
  void simularScore(double s) => _onScore?.call(s);
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
    void Function(double score)? onScore,
  }) async {
    throw Exception('ONNX no cargó (simulado)');
  }

  @override
  void fijarUmbral(double umbral) {}
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

  test('fuente única de verdad: modoVozActivo true pausa, false reanuda',
      () async {
    SharedPreferences.setMockInitialValues({'wakeword_activo': true});
    final fake = _FakeEscucha();
    final c = hacerContainer(fake);
    final ctrl = c.read(wakeWordControllerProvider.notifier);
    await ctrl.alFrente(); // escuchando
    expect(fake.iniciarCount, 1);

    // Entra el modo voz (manos libres) → el listener pausa.
    c.read(modoVozActivoProvider.notifier).state = true;
    await pumpEventQueue();
    expect(fake.detenerCount, greaterThanOrEqualTo(1));
    expect(c.read(wakeWordControllerProvider).fase, FaseWakeWord.pausadoPorVoz);

    // Sale el modo voz por CUALQUIER vía → el listener reanuda solo.
    c.read(modoVozActivoProvider.notifier).state = false;
    await pumpEventQueue();
    expect(fake.iniciarCount, 2);
    expect(c.read(wakeWordControllerProvider).fase, FaseWakeWord.escuchando);
  });

  test('cambiarUmbral persiste y lo aplica en vivo', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = _FakeEscucha();
    final c = hacerContainer(fake);
    final ctrl = c.read(wakeWordControllerProvider.notifier);
    await ctrl.cambiarUmbral(0.25);
    expect(fake.umbralFijado, 0.25); // aplicado en vivo al pipeline
    expect(await ctrl.umbral(), 0.25); // persistido
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

  test('el score se refleja en el estado (maxScore) para verlo en Ajustes',
      () async {
    SharedPreferences.setMockInitialValues({'wakeword_activo': true});
    final fake = _FakeEscucha();
    final c = hacerContainer(fake);
    final ctrl = c.read(wakeWordControllerProvider.notifier);
    await ctrl.alFrente(); // escuchando

    fake.simularScore(0.12);
    fake.simularScore(0.73); // nuevo máximo
    fake.simularScore(0.40);

    // maxScore retiene el pico (lo que importa para ver si cruza el umbral).
    final s = c.read(wakeWordControllerProvider);
    expect(s.maxScore, 0.73);
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

  // ── Motor en SEGUNDO PLANO (foreground service nativo) ────────────────
  //
  // Con "escuchar en segundo plano" ON, el motor del wake word es el FGS
  // nativo (no el pipeline in-app), y se arranca DESDE PRIMER PLANO — clave en
  // Android 14+, donde un FGS de micrófono no puede iniciarse desde background.

  /// Captura las llamadas salientes al canal nativo del bg service.
  List<String> espiarCanalBg() {
    final llamadas = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.matix.matix/wakeword_bg'),
      (call) async {
        llamadas.add(call.method);
        return true;
      },
    );
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.matix.matix/wakeword_bg'),
          null,
        ));
    return llamadas;
  }

  test('segundo plano ON: el motor es el FGS, no el in-app', () async {
    SharedPreferences.setMockInitialValues({
      'wakeword_activo': true,
      'wakeword_bg_activo': true,
    });
    final bg = espiarCanalBg();
    final fake = _FakeEscucha();
    final c = hacerContainer(fake);
    final ctrl = c.read(wakeWordControllerProvider.notifier);

    await ctrl.alFrente();
    // El in-app NO se usa como motor; el FGS nativo SÍ arranca.
    expect(fake.iniciarCount, 0);
    expect(bg.contains('iniciar'), isTrue);
    expect(c.read(wakeWordControllerProvider).fase, FaseWakeWord.escuchando);
  });

  test('segundo plano ON: a fondo el FGS sigue (no se detiene)', () async {
    SharedPreferences.setMockInitialValues({
      'wakeword_activo': true,
      'wakeword_bg_activo': true,
    });
    final bg = espiarCanalBg();
    final fake = _FakeEscucha();
    final c = hacerContainer(fake);
    final ctrl = c.read(wakeWordControllerProvider.notifier);

    await ctrl.alFrente();
    bg.clear();
    await ctrl.alFondo();
    // No se manda 'detener' al ir a background: el FGS debe seguir vivo.
    expect(bg.contains('detener'), isFalse);
  });

  test('segundo plano ON: manos libres suelta el FGS y al volver lo retoma',
      () async {
    SharedPreferences.setMockInitialValues({
      'wakeword_activo': true,
      'wakeword_bg_activo': true,
    });
    final bg = espiarCanalBg();
    final fake = _FakeEscucha();
    final c = hacerContainer(fake);
    final ctrl = c.read(wakeWordControllerProvider.notifier);

    await ctrl.alFrente();
    bg.clear();
    ctrl.pausarPorVoz(); // manos libres toma el micro
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(bg.contains('detener'), isTrue);

    bg.clear();
    await ctrl.reanudarTrasVoz(); // manos libres terminó
    expect(bg.contains('iniciar'), isTrue);
  });

  test('fijarBgActivo(true) cambia el motor a FGS desde primer plano',
      () async {
    SharedPreferences.setMockInitialValues({'wakeword_activo': true});
    final bg = espiarCanalBg();
    final fake = _FakeEscucha();
    final c = hacerContainer(fake);
    final ctrl = c.read(wakeWordControllerProvider.notifier);

    await ctrl.alFrente(); // arranca in-app (bg off)
    expect(fake.iniciarCount, 1);

    bg.clear();
    await ctrl.fijarBgActivo(true); // pasa a FGS
    expect(bg.contains('iniciar'), isTrue);
    expect(c.read(wakeWordControllerProvider).fase, FaseWakeWord.escuchando);
  });
}
