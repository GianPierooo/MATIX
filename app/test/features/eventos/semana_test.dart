import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/eventos/domain/semana.dart';

/// Tests de los helpers de semana de la vista de calendario.

void main() {
  group('lunesDe', () {
    test('un miércoles → el lunes de esa semana', () {
      // 2026-06-10 es miércoles → lunes 2026-06-08.
      expect(lunesDe(DateTime(2026, 6, 10, 15, 30)), DateTime(2026, 6, 8));
    });

    test('un lunes se devuelve a sí mismo (a medianoche)', () {
      expect(lunesDe(DateTime(2026, 6, 8, 23, 0)), DateTime(2026, 6, 8));
    });

    test('un domingo → el lunes anterior', () {
      // 2026-06-14 es domingo → lunes 2026-06-08.
      expect(lunesDe(DateTime(2026, 6, 14)), DateTime(2026, 6, 8));
    });

    test('cruza el cambio de mes', () {
      // 2026-07-01 es miércoles → lunes 2026-06-29.
      expect(lunesDe(DateTime(2026, 7, 1)), DateTime(2026, 6, 29));
    });
  });

  group('diasDeSemana', () {
    test('7 días consecutivos de lunes a domingo', () {
      final dias = diasDeSemana(DateTime(2026, 6, 10));
      expect(dias.length, 7);
      expect(dias.first, DateTime(2026, 6, 8)); // lunes
      expect(dias.last, DateTime(2026, 6, 14)); // domingo
      // Días ISO 1..7 (lunes..domingo).
      expect([for (final d in dias) d.weekday], [1, 2, 3, 4, 5, 6, 7]);
    });
  });
}
