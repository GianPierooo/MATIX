import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/proyectos/domain/bloque_protegido.dart';

void main() {
  group('BloqueProtegido.parse', () {
    test('caso típico Matix L/Mi/V 6-9 am', () {
      final b = BloqueProtegido.parse({
        'dias_semana': [0, 2, 4],
        'hora_inicio': '06:00',
        'hora_fin': '09:00',
      });
      expect(b, isNotNull);
      expect(b!.legible(), 'L / Mi / V  ·  06:00 – 09:00');
    });

    test('null entrada devuelve null', () {
      expect(BloqueProtegido.parse(null), isNull);
    });

    test('falta hora_inicio devuelve null', () {
      expect(
        BloqueProtegido.parse({
          'dias_semana': [0],
          'hora_fin': '09:00',
        }),
        isNull,
      );
    });

    test('dias_semana fuera de rango se filtran', () {
      final b = BloqueProtegido.parse({
        'dias_semana': [0, 99, 3],
        'hora_inicio': '06:00',
        'hora_fin': '09:00',
      });
      expect(b!.diasSemana, [0, 3]);
    });

    test('dias_semana vacíos devuelve null', () {
      expect(
        BloqueProtegido.parse({
          'dias_semana': <int>[],
          'hora_inicio': '06:00',
          'hora_fin': '09:00',
        }),
        isNull,
      );
    });
  });
}
