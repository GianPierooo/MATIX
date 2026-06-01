import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
