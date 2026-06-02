import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/wakeword/data/wakeword_muestras_guion.dart';
import 'package:matix/features/wakeword/data/wakeword_muestras_repository.dart';

void main() {
  group('guion de entrenamiento de voz', () {
    final guion = construirGuion();

    test('tiene 60 positivos y 25 negativos (85 total)', () {
      final pos = guion.where((m) => m.esPositivo).length;
      final neg = guion.where((m) => !m.esPositivo).length;
      expect(pos, 60);
      expect(neg, 25);
      expect(guion.length, 85);
    });

    test('todos los positivos dicen "oye matix"', () {
      for (final m in guion.where((m) => m.esPositivo)) {
        expect(m.frase, 'oye matix');
      }
    });

    test('los positivos van primero y luego los negativos (orden)', () {
      final tipos = guion.map((m) => m.tipo).toList();
      final primerNegativo = tipos.indexOf('negativo');
      // No hay ningún positivo después del primer negativo.
      expect(tipos.sublist(primerNegativo).contains('positivo'), isFalse);
    });

    test('cada ítem trae una pista no vacía', () {
      for (final m in guion) {
        expect(m.pista.trim(), isNotEmpty);
      }
    });
  });

  group('ConteoMuestras.fromJson', () {
    test('parsea positivo/negativo/total', () {
      final c = ConteoMuestras.fromJson(
        {'positivo': 12, 'negativo': 3, 'total': 15},
      );
      expect(c.positivo, 12);
      expect(c.negativo, 3);
      expect(c.total, 15);
    });

    test('campos ausentes → 0', () {
      final c = ConteoMuestras.fromJson({});
      expect(c.positivo, 0);
      expect(c.negativo, 0);
      expect(c.total, 0);
    });
  });
}
