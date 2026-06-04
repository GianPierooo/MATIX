import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/live_camara/domain/muestreo.dart';

void main() {
  const pol = PoliticaMuestreo(); // intervalo 3s, tope 18/min, sesión 3min, umbral 12, estáticos 5
  final t0 = DateTime(2026, 6, 4, 10, 0, 0);

  group('detección de cambio', () {
    test('diferenciaFrames promedia el valor absoluto', () {
      expect(diferenciaFrames([10, 10, 10], [10, 10, 10]), 0);
      expect(diferenciaFrames([0, 0], [10, 20]), 15);
      expect(diferenciaFrames(null, [1, 2]), 255); // sin previa = máximo
      expect(diferenciaFrames([1, 2], [1]), 255); // largos distintos
    });

    test('hayCambioSignificativo respeta el umbral', () {
      expect(hayCambioSignificativo(null, [5, 5], 12), isTrue); // sin previa
      expect(hayCambioSignificativo([100, 100], [104, 104], 12), isFalse); // dif 4 < 12
      expect(hayCambioSignificativo([100, 100], [130, 130], 12), isTrue); // dif 30 ≥ 12
    });
  });

  group('decidirEnvio (muestreo)', () {
    test('respeta el intervalo entre envíos', () {
      final d = decidirEnvio(
        ahora: t0.add(const Duration(seconds: 1)),
        ultimoEnvio: t0,
        hayCambio: true,
        framesUltimoMinuto: 0,
        politica: pol,
      );
      expect(d.enviar, isFalse);
      expect(d.motivo, MotivoNoEnvio.intervalo);
    });

    test('frame redundante (sin cambio) NO se envía', () {
      final d = decidirEnvio(
        ahora: t0.add(const Duration(seconds: 5)),
        ultimoEnvio: t0,
        hayCambio: false,
        framesUltimoMinuto: 0,
        politica: pol,
      );
      expect(d.enviar, isFalse);
      expect(d.motivo, MotivoNoEnvio.sinCambio);
    });

    test('tope por minuto frena aunque haya cambio', () {
      final d = decidirEnvio(
        ahora: t0.add(const Duration(seconds: 5)),
        ultimoEnvio: t0,
        hayCambio: true,
        framesUltimoMinuto: 18,
        politica: pol,
      );
      expect(d.enviar, isFalse);
      expect(d.motivo, MotivoNoEnvio.topeMinuto);
    });

    test('pasa intervalo + cambio + bajo el tope → se envía', () {
      final d = decidirEnvio(
        ahora: t0.add(const Duration(seconds: 4)),
        ultimoEnvio: t0,
        hayCambio: true,
        framesUltimoMinuto: 3,
        politica: pol,
      );
      expect(d.enviar, isTrue);
      expect(d.motivo, isNull);
    });

    test('primer frame (sin ultimoEnvio) se envía', () {
      final d = decidirEnvio(
        ahora: t0,
        ultimoEnvio: null,
        hayCambio: true,
        framesUltimoMinuto: 0,
        politica: pol,
      );
      expect(d.enviar, isTrue);
    });
  });

  group('framesEnUltimoMinuto', () {
    test('cuenta solo los del último minuto', () {
      final envios = [
        t0.add(const Duration(seconds: 5)),
        t0.add(const Duration(seconds: 30)),
        t0.add(const Duration(seconds: 65)), // este es > 1 min antes de t=70..
      ];
      final ahora = t0.add(const Duration(seconds: 70));
      // hace <60s: el de 30s (40s atrás) y el de 65s (5s atrás); el de 5s (65s atrás) NO.
      expect(framesEnUltimoMinuto(envios, ahora), 2);
    });
  });

  group('debeCortar (auto-corte, guardrail de costo)', () {
    test('corta al pasar el tope de sesión', () {
      final c = debeCortar(
        inicio: t0,
        ahora: t0.add(const Duration(minutes: 3)),
        estaticosSeguidos: 0,
        politica: pol,
      );
      expect(c.cortar, isTrue);
      expect(c.razon, RazonCorte.topeSesion);
    });

    test('corta tras N frames seguidos sin cambio', () {
      final c = debeCortar(
        inicio: t0,
        ahora: t0.add(const Duration(seconds: 30)),
        estaticosSeguidos: 5,
        politica: pol,
      );
      expect(c.cortar, isTrue);
      expect(c.razon, RazonCorte.sinCambios);
    });

    test('no corta si va en tiempo y con cambios', () {
      final c = debeCortar(
        inicio: t0,
        ahora: t0.add(const Duration(seconds: 30)),
        estaticosSeguidos: 1,
        politica: pol,
      );
      expect(c.cortar, isFalse);
    });
  });

  group('costoEstimadoUsd', () {
    test('suma visión por frame + TTS por carácter', () {
      // 10 frames + 200 chars TTS.
      final c = costoEstimadoUsd(framesEnviados: 10, caracteresTts: 200);
      expect(c, closeTo(10 * kCostoFrameUsd + 200 * kCostoTtsPorChar, 1e-9));
      expect(costoEstimadoUsd(framesEnviados: 0, caracteresTts: 0), 0);
    });
  });
}
