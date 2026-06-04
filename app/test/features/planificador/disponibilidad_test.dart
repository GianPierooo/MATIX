import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/planificador/domain/disponibilidad.dart';

/// Tests del modelo de disponibilidad por día: que cada día tenga su propia
/// ventana y que los días no disponibles no la tengan. (El cálculo de huecos y
/// la colocación del plan viven ahora en la capa de horario del cerebro.)

void main() {
  group('DisponibilidadSemanal por día', () {
    test('ventana distinta por día (lun-vie 18-22, sáb-dom 9-13)', () {
      final disp = DisponibilidadSemanal({
        for (var d = 1; d <= 5; d++)
          d: const DisponibilidadDia(inicio: 18, fin: 22),
        6: const DisponibilidadDia(inicio: 9, fin: 13),
        7: const DisponibilidadDia(inicio: 9, fin: 13),
      });
      // 2026-06-10 es miércoles (día 3) → 18-22.
      expect(disp.ventanaDe(DateTime(2026, 6, 10))!.inicio, 18);
      expect(disp.ventanaDe(DateTime(2026, 6, 10))!.fin, 22);
      // 2026-06-13 es sábado (día 6) → 9-13.
      expect(disp.ventanaDe(DateTime(2026, 6, 13))!.inicio, 9);
      expect(disp.ventanaDe(DateTime(2026, 6, 13))!.fin, 13);
    });

    test('día no disponible → sin ventana', () {
      final disp = DisponibilidadSemanal({
        3: const DisponibilidadDia(activo: false),
      });
      expect(disp.ventanaDe(DateTime(2026, 6, 10)), isNull); // miércoles
    });

    test('día ausente cuenta como no disponible', () {
      final disp = DisponibilidadSemanal(const {});
      expect(disp.diaDe(2).activo, isFalse);
      expect(disp.ventanaDe(DateTime(2026, 6, 9)), isNull);
    });

    test('conDia copia con un día cambiado', () {
      final base = DisponibilidadSemanal.porDefecto;
      final cambiado = base.conDia(1, const DisponibilidadDia(inicio: 6, fin: 10));
      expect(cambiado.diaDe(1).inicio, 6);
      expect(cambiado.diaDe(2).inicio, 9); // los demás intactos
    });
  });
}
