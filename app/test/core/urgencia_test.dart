import 'package:flutter_test/flutter_test.dart';
import 'package:matix/core/urgencia.dart';
import 'package:matix/theme/matix_colors.dart';

/// Tests de la lógica pura de urgencia (Urgencia-1): cálculo del tiempo
/// restante, estado vencido y escala de color por cercanía. `ahora` se
/// pasa explícito para que todo sea determinístico.

void main() {
  final ahora = DateTime(2026, 5, 28, 12, 0);

  group('nivelUrgencia', () {
    test('falta mucho → tranquilo', () {
      final objetivo = ahora.add(const Duration(days: 5));
      expect(nivelUrgencia(objetivo, ahora), NivelUrgencia.tranquilo);
    });

    test('dentro de 72 h pero más de 24 h → próximo (ámbar)', () {
      final objetivo = ahora.add(const Duration(hours: 48));
      expect(nivelUrgencia(objetivo, ahora), NivelUrgencia.proximo);
    });

    test('dentro de 24 h → urgente (rojo)', () {
      final objetivo = ahora.add(const Duration(hours: 10));
      expect(nivelUrgencia(objetivo, ahora), NivelUrgencia.urgente);
    });

    test('ya pasó → vencido', () {
      final objetivo = ahora.subtract(const Duration(minutes: 1));
      expect(nivelUrgencia(objetivo, ahora), NivelUrgencia.vencido);
    });

    test('escala completa al acercarse el mismo objetivo', () {
      final objetivo = DateTime(2026, 5, 30, 12, 0); // límite fijo
      // 4 días antes → tranquilo
      expect(nivelUrgencia(objetivo, DateTime(2026, 5, 26, 12, 0)),
          NivelUrgencia.tranquilo);
      // 2 días antes (48 h) → próximo
      expect(nivelUrgencia(objetivo, DateTime(2026, 5, 28, 12, 0)),
          NivelUrgencia.proximo);
      // 6 h antes → urgente
      expect(nivelUrgencia(objetivo, DateTime(2026, 5, 30, 6, 0)),
          NivelUrgencia.urgente);
      // pasado → vencido
      expect(nivelUrgencia(objetivo, DateTime(2026, 5, 30, 12, 1)),
          NivelUrgencia.vencido);
    });

    test('límites exactos: 24 h es urgente, 72 h es próximo', () {
      expect(nivelUrgencia(ahora.add(const Duration(hours: 24)), ahora),
          NivelUrgencia.urgente);
      expect(nivelUrgencia(ahora.add(const Duration(hours: 72)), ahora),
          NivelUrgencia.proximo);
    });
  });

  group('colorUrgencia', () {
    test('tranquilo es muted, próximo ámbar, urgente y vencido rojos', () {
      expect(colorUrgencia(NivelUrgencia.tranquilo), MatixColors.muted);
      expect(colorUrgencia(NivelUrgencia.proximo), MatixColors.amber);
      expect(colorUrgencia(NivelUrgencia.urgente), MatixColors.red);
      expect(colorUrgencia(NivelUrgencia.vencido), MatixColors.red);
    });
  });

  group('textoUrgencia', () {
    test('futuro: días, horas y minutos según corresponda', () {
      expect(textoUrgencia(ahora.add(const Duration(days: 2)), ahora),
          'En 2 días');
      expect(textoUrgencia(ahora.add(const Duration(days: 1)), ahora),
          'En 1 día');
      expect(textoUrgencia(ahora.add(const Duration(hours: 5)), ahora),
          'En 5 h');
      expect(textoUrgencia(ahora.add(const Duration(minutes: 12)), ahora),
          'En 12 min');
    });

    test('vencido: cuenta hacia atrás, sin reproche', () {
      expect(textoUrgencia(ahora.subtract(const Duration(days: 3)), ahora),
          'Hace 3 días');
      expect(textoUrgencia(ahora.subtract(const Duration(hours: 2)), ahora),
          'Hace 2 h');
    });

    test('al filo: "Justo ahora" y "Recién"', () {
      expect(textoUrgencia(ahora.add(const Duration(seconds: 20)), ahora),
          'Justo ahora');
      expect(textoUrgencia(ahora.subtract(const Duration(seconds: 20)), ahora),
          'Recién');
    });

    test('singular vs plural en días', () {
      expect(textoUrgencia(ahora.subtract(const Duration(days: 1)), ahora),
          'Hace 1 día');
    });
  });
}
