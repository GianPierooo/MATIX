import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/rollover/domain/rollover.dart';

void main() {
  group('RolloverData.fromJson', () {
    test('parsea propuestas y sobrecarga completas', () {
      final data = RolloverData.fromJson({
        'proposals': [
          {
            'tarea_id': 't1',
            'titulo': 'Informe',
            'veces_reprogramada': 2,
            'vencio_en': '2026-06-04T10:00:00Z',
            'propuesta': {
              'fecha': '2026-06-06',
              'inicio': '09:00',
              'fin': '09:20',
              'cuando': 'mañana 09:00',
            },
          },
        ],
        'sobrecarga': {
          'sobrecargado': true,
          'n': 6,
          'peor_titulo': 'Informe',
          'peor_veces': 3,
          'mensaje': 'Esto ya lo moviste 3 veces.',
          'recomendacion': 'reescopar',
        },
      });

      expect(data.proposals.length, 1);
      final p = data.proposals.first;
      expect(p.tareaId, 't1');
      expect(p.titulo, 'Informe');
      expect(p.vecesReprogramada, 2);
      expect(p.propuesta?.cuando, 'mañana 09:00');
      expect(data.sobrecarga.sobrecargado, isTrue);
      expect(data.sobrecarga.recomendacion, 'reescopar');
      expect(data.hayAlgo, isTrue);
    });

    test('propuesta nula (sin hueco) no rompe', () {
      final data = RolloverData.fromJson({
        'proposals': [
          {'tarea_id': 't2', 'titulo': 'Sin hueco', 'propuesta': null},
        ],
        'sobrecarga': {'sobrecargado': false, 'n': 1},
      });
      expect(data.proposals.first.propuesta, isNull);
      expect(data.proposals.first.vecesReprogramada, 0);
      expect(data.sobrecarga.sobrecargado, isFalse);
      expect(data.hayAlgo, isTrue);
    });

    test('vacío → sin nada', () {
      final data = RolloverData.fromJson({'proposals': [], 'sobrecarga': null});
      expect(data.proposals, isEmpty);
      expect(data.sobrecarga.sobrecargado, isFalse);
      expect(data.hayAlgo, isFalse);
    });

    test('decisiones serializan al id del cerebro', () {
      expect(DecisionRollover.aceptar.id, 'aceptar');
      expect(DecisionRollover.otroDia.id, 'otro_dia');
      expect(DecisionRollover.soltar.id, 'soltar');
    });
  });
}
