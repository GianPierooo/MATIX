import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/mascota/domain/dosificacion.dart';

void main() {
  group('enSilencio', () {
    test('ventana normal (no cruza medianoche)', () {
      expect(enSilencio(13, 22, 8), isFalse);
      expect(enSilencio(23, 22, 8), isTrue); // cruza: 22→8
      expect(enSilencio(2, 22, 8), isTrue);
      expect(enSilencio(8, 22, 8), isFalse); // fin exclusivo
    });
    test('inicio == fin → nunca en silencio', () {
      expect(enSilencio(3, 0, 0), isFalse);
    });
  });

  group('anti-fatiga', () {
    test('factor sube por tramos', () {
      expect(factorIgnoradas(0), 1);
      expect(factorIgnoradas(1), 1);
      expect(factorIgnoradas(2), 2);
      expect(factorIgnoradas(3), 2);
      expect(factorIgnoradas(4), 4);
    });
    test('intervalo normal vs discreta escala con el factor', () {
      expect(intervaloAparicion(FrecuenciaMascota.normal, 0),
          const Duration(hours: 4));
      expect(intervaloAparicion(FrecuenciaMascota.discreta, 0),
          const Duration(hours: 8));
      expect(intervaloAparicion(FrecuenciaMascota.normal, 4),
          const Duration(hours: 16)); // 4h × 4
    });
  });

  group('puedeAparecer', () {
    final ahora = DateTime(2026, 6, 4, 15); // 15:00, fuera de silencio
    test('apagada nunca aparece', () {
      expect(
        puedeAparecer(
          habilitado: false,
          ahora: ahora,
          ultima: null,
          ignoradasSeguidas: 0,
          silencioInicio: 22,
          silencioFin: 8,
          frecuencia: FrecuenciaMascota.normal,
        ),
        isFalse,
      );
    });
    test('en silencio no aparece aunque toque', () {
      final noche = DateTime(2026, 6, 4, 23);
      expect(
        puedeAparecer(
          habilitado: true,
          ahora: noche,
          ultima: null,
          ignoradasSeguidas: 0,
          silencioInicio: 22,
          silencioFin: 8,
          frecuencia: FrecuenciaMascota.normal,
        ),
        isFalse,
      );
    });
    test('sin historial aparece; dentro del intervalo no; pasado sí', () {
      bool puede(DateTime? ultima) => puedeAparecer(
            habilitado: true,
            ahora: ahora,
            ultima: ultima,
            ignoradasSeguidas: 0,
            silencioInicio: 22,
            silencioFin: 8,
            frecuencia: FrecuenciaMascota.normal,
          );
      expect(puede(null), isTrue);
      expect(puede(ahora.subtract(const Duration(hours: 1))), isFalse);
      expect(puede(ahora.subtract(const Duration(hours: 5))), isTrue);
    });
    test('si la ignoras, el intervalo se alarga (baja el volumen)', () {
      final ultima = ahora.subtract(const Duration(hours: 5));
      // 5 h pasó el umbral normal (4 h)…
      expect(
        puedeAparecer(
          habilitado: true,
          ahora: ahora,
          ultima: ultima,
          ignoradasSeguidas: 0,
          silencioInicio: 22,
          silencioFin: 8,
          frecuencia: FrecuenciaMascota.normal,
        ),
        isTrue,
      );
      // …pero con 4 ignoradas el umbral es 16 h, así que 5 h aún no alcanza.
      expect(
        puedeAparecer(
          habilitado: true,
          ahora: ahora,
          ultima: ultima,
          ignoradasSeguidas: 4,
          silencioInicio: 22,
          silencioFin: 8,
          frecuencia: FrecuenciaMascota.normal,
        ),
        isFalse,
      );
    });
  });

  group('puedeDespedir', () {
    final ahora = DateTime(2026, 6, 4, 15);
    test('respeta silencio y el mínimo entre despedidas', () {
      expect(
        puedeDespedir(
          habilitado: true,
          ahora: ahora,
          ultimaDespedida: null,
          silencioInicio: 22,
          silencioFin: 8,
        ),
        isTrue,
      );
      expect(
        puedeDespedir(
          habilitado: true,
          ahora: ahora,
          ultimaDespedida: ahora.subtract(const Duration(hours: 1)),
          silencioInicio: 22,
          silencioFin: 8,
        ),
        isFalse,
      );
    });
  });
}
