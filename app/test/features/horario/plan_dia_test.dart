import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/horario/domain/plan_dia.dart';

void main() {
  group('helpers de hora', () {
    test('minDesdeHHMM / hhmmDesdeMin ida y vuelta', () {
      expect(minDesdeHHMM('07:30'), 450);
      expect(minDesdeHHMM('00:00'), 0);
      expect(minDesdeHHMM('basura'), 0);
      expect(hhmmDesdeMin(450), '07:30');
      expect(hhmmDesdeMin(8 * 60), '08:00');
    });

    test('hueco entre bloques y visibilidad', () {
      expect(huecoMin('10:00', '10:45'), 45);
      expect(huecoMin('10:00', '10:10'), 10);
      expect(huecoVisible('10:00', '10:45'), isTrue);
      expect(huecoVisible('10:00', '10:10'), isFalse); // micro-hueco, no se muestra
    });

    test('argbDeHex parsea hex de curso', () {
      expect(argbDeHex('#2D7FF9'), 0xFF2D7FF9);
      expect(argbDeHex('2D7FF9'), isNull); // sin #
      expect(argbDeHex('#zzz'), isNull);
      expect(argbDeHex(null), isNull);
    });
  });

  group('parseo del plan', () {
    final json = {
      'fecha': '2026-06-04',
      'despierta': '07:00',
      'duerme': '23:00',
      'desde': null,
      'bloques': [
        {
          'inicio': '07:00',
          'fin': '07:45',
          'titulo': 'Calistenia',
          'tipo': 'ancla',
          'tentativo': false,
        },
        {
          'inicio': '08:00',
          'fin': '09:30',
          'titulo': 'OneXotic: sprint',
          'tipo': 'trabajo',
          'tentativo': true,
          'proyecto': 'OneXotic',
          'nodo_id': 'n1',
          'set_item_id': 's1',
        },
      ],
      'fuera': [
        {'titulo': 'Práctica: Guitarra', 'tipo': 'skill', 'motivo': 'no entró en las ventanas de hoy'},
      ],
    };

    test('PlanDia.fromJson arma bloques y fuera', () {
      final plan = PlanDia.fromJson(json);
      expect(plan.fecha, '2026-06-04');
      expect(plan.bloques.length, 2);
      expect(plan.fuera.length, 1);
      expect(plan.vacio, isFalse);
      expect(plan.esReplan, isFalse);
    });

    test('distingue fijo vs tentativo', () {
      final plan = PlanDia.fromJson(json);
      final ancla = plan.bloques[0];
      final trabajo = plan.bloques[1];
      expect(ancla.esFijo, isTrue);
      expect(trabajo.tentativo, isTrue);
      expect(plan.tentativos.length, 1);
      expect(trabajo.proyecto, 'OneXotic');
    });

    test('clave usa ids reales y conHoras conserva identidad', () {
      final plan = PlanDia.fromJson(json);
      final trabajo = plan.bloques[1];
      expect(trabajo.clave, 'n1'); // tareaId null → nodoId
      final movido = trabajo.conHoras('10:00', '11:30');
      expect(movido.inicio, '10:00');
      expect(movido.fin, '11:30');
      expect(movido.clave, 'n1'); // misma identidad tras editar la hora
      expect(movido.setItemId, 's1');
    });

    test('esReplan cuando viene desde', () {
      final plan = PlanDia.fromJson({...json, 'desde': '16:30'});
      expect(plan.esReplan, isTrue);
      expect(plan.desde, '16:30');
    });
  });
}
