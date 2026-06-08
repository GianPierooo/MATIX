import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/push/domain/pendientes_confirmacion.dart';

void main() {
  group('PendientesConfirmacion.fromJson', () {
    test('parsea tareas y eventos con campos esperados', () {
      final p = PendientesConfirmacion.fromJson({
        'tareas': [
          {'id': 't1', 'titulo': 'Estudiar', 'vencio_hace_min': 35},
        ],
        'eventos': [
          {'id': 'e1', 'titulo': 'Cálculo', 'ubicacion': 'La uni',
           'termino_hace_min': 90},
        ],
      });
      expect(p.tareas.single.id, 't1');
      expect(p.tareas.single.vencioHaceMin, 35);
      expect(p.eventos.single.titulo, 'Cálculo');
      expect(p.eventos.single.ubicacion, 'La uni');
      expect(p.vacio, isFalse);
      expect(p.total, 2);
    });

    test('listas faltantes → vacío sin crashear', () {
      final p = PendientesConfirmacion.fromJson(const {});
      expect(p.vacio, isTrue);
      expect(p.total, 0);
    });
  });

  group('humanoDesde', () {
    test('formatea en español', () {
      expect(humanoDesde(0), 'hace un momento');
      expect(humanoDesde(5), 'hace 5 min');
      expect(humanoDesde(59), 'hace 59 min');
      expect(humanoDesde(60), 'hace 1 h');
      expect(humanoDesde(150), 'hace 2 h 30 min');
    });
  });
}
