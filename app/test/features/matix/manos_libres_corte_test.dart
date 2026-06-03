import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/matix/data/tts_service.dart';
import 'package:matix/features/matix/providers/manos_libres_providers.dart';
import 'package:matix/features/wakeword/providers/wakeword_providers.dart';

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

  group('saludoWakeWord', () {
    test('sin conversación: saludo simple', () {
      final s = saludoWakeWord(hayConversacion: false);
      expect(s, '¡Hola, Piero!');
      expect(s.contains('*'), isFalse); // sin asteriscos
    });

    test('con conversación: ofrece retomar', () {
      final s = saludoWakeWord(hayConversacion: true);
      expect(s.contains('Piero'), isTrue);
      expect(s.toLowerCase().contains('seguimos'), isTrue);
      expect(s.contains('*'), isFalse);
    });
  });

  test('salir() SUELTA el relevo de micro (modoVozActivo=false)', () async {
    // Regresión del bug "se queda en una conversación": el reset del flag debe
    // vivir en salir() (vía que siempre corre), no en el dispose() del widget.
    final fake = _FakeTts();
    final c = hacerContainer(fake);
    final notifier = c.read(manosLibresProvider.notifier);

    // Simulamos modo voz activo (como tras entrar()).
    c.read(modoVozActivoProvider.notifier).state = true;
    expect(c.read(modoVozActivoProvider), isTrue);

    await notifier.salir();

    // El wake word puede reanudar: el flag quedó liberado.
    expect(c.read(modoVozActivoProvider), isFalse);
  });
}
