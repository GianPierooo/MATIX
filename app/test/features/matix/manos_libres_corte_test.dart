import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/matix/data/tts_service.dart';
import 'package:matix/features/matix/providers/manos_libres_providers.dart';

/// TTS fake que solo registra si se llamó `detener` (el corte del audio).
class _FakeTts implements TtsBase {
  int detenerCount = 0;

  @override
  Future<void> hablar(String texto, {void Function()? onInicio}) async {
    onInicio?.call();
  }

  @override
  Future<void> detener() async => detenerCount++;

  @override
  Future<void> dispose() async {}
}

void main() {
  ProviderContainer hacerContainer(_FakeTts fake) {
    final c = ProviderContainer(
      overrides: [ttsManosLibresProvider.overrideWithValue(fake)],
    );
    // Mantener vivo el provider autoDispose durante el test.
    final sub = c.listen(manosLibresProvider, (_, _) {});
    addTearDown(sub.close);
    addTearDown(c.dispose);
    return c;
  }

  test('interrumpir: apaga la onda (reproduciendo=false) y corta el audio',
      () async {
    final fake = _FakeTts();
    final c = hacerContainer(fake);
    final notifier = c.read(manosLibresProvider.notifier);

    notifier.debugFijarReproduccion(
      FaseManosLibres.hablando,
      reproduciendo: true,
    );
    expect(c.read(manosLibresProvider).reproduciendo, isTrue);

    await notifier.interrumpirHabla();

    // Visual y audio paran JUNTOS.
    expect(c.read(manosLibresProvider).reproduciendo, isFalse);
    expect(fake.detenerCount, 1);
  });

  test('pausar durante el habla: apaga la onda + corta + queda en pausa',
      () async {
    final fake = _FakeTts();
    final c = hacerContainer(fake);
    final notifier = c.read(manosLibresProvider.notifier);

    notifier.debugFijarReproduccion(
      FaseManosLibres.hablando,
      reproduciendo: true,
    );

    await notifier.pausar();

    final s = c.read(manosLibresProvider);
    expect(s.reproduciendo, isFalse);
    expect(s.fase, FaseManosLibres.enPausa);
    expect(fake.detenerCount, 1);
  });

  test('interrumpir no hace nada si no está hablando', () async {
    final fake = _FakeTts();
    final c = hacerContainer(fake);
    final notifier = c.read(manosLibresProvider.notifier);

    notifier.debugFijarReproduccion(FaseManosLibres.escuchando);
    await notifier.interrumpirHabla();
    expect(fake.detenerCount, 0);
  });
}
