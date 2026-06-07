import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/horario/data/despertar_prefs.dart';

void main() {
  group('fechaIso', () {
    test('formatea yyyy-MM-dd con padding e ignora la hora', () {
      expect(fechaIso(DateTime(2026, 6, 7)), '2026-06-07');
      expect(fechaIso(DateTime(2026, 12, 25, 23, 59)), '2026-12-25');
      expect(fechaIso(DateTime(2026, 1, 3, 0, 1)), '2026-01-03');
    });
  });

  group('despertarRegistradoHoy', () {
    final hoy = DateTime(2026, 6, 7, 9, 30);

    test('sin fecha guardada → no registrado (el botón se muestra)', () {
      expect(despertarRegistradoHoy(null, hoy), isFalse);
    });

    test('fecha de hoy → registrado (el botón se oculta)', () {
      expect(despertarRegistradoHoy('2026-06-07', hoy), isTrue);
    });

    test('fecha de ayer → no registrado (reaparece al día siguiente)', () {
      expect(despertarRegistradoHoy('2026-06-06', hoy), isFalse);
    });

    test('cruce de medianoche: la marca de ayer ya no cuenta hoy', () {
      final medianoche = DateTime(2026, 6, 8, 0, 5);
      expect(despertarRegistradoHoy('2026-06-07', medianoche), isFalse);
    });
  });
}
