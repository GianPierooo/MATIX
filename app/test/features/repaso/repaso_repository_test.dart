import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/repaso/data/repaso_repository.dart';

/// Tests del parseo del repaso semanal (Capa 8 · Repaso). La síntesis
/// la hace el cerebro; acá verificamos que la app lee bien el JSON,
/// incluidas las tareas que se pasaron (con id, para reprogramar).

void main() {
  test('RepasoSemanal.fromJson parsea síntesis, focos y vencidas', () {
    final j = {
      'semana_desde': '2026-06-08',
      'semana_hasta': '2026-06-14',
      'resumen': 'Buena semana: avanzaste y quedó poco suelto.',
      'focos': ['Cerrar lo pendiente', 'Avanzar la tesis'],
      'completadas': 5,
      'eventos': 3,
      'apuntes_nuevos': 2,
      'vencidas': [
        {
          'id': 't1',
          'titulo': 'Entregar informe',
          'contexto': 'Tesis',
          'vence_en': '2026-06-09T15:00:00+00:00',
        },
        {'id': 't2', 'titulo': 'Llamar al banco'},
      ],
    };

    final r = RepasoSemanal.fromJson(j);
    expect(r.semanaDesde, '2026-06-08');
    expect(r.resumen, startsWith('Buena semana'));
    expect(r.focos, ['Cerrar lo pendiente', 'Avanzar la tesis']);
    expect(r.completadas, 5);
    expect(r.eventos, 3);
    expect(r.apuntesNuevos, 2);
    expect(r.vencidas, hasLength(2));
    expect(r.vencidas.first.id, 't1');
    expect(r.vencidas.first.contexto, 'Tesis');
    expect(r.vencidas[1].contexto, isNull);
  });

  test('fromJson tolera campos ausentes', () {
    final r = RepasoSemanal.fromJson({
      'semana_desde': '2026-06-08',
      'semana_hasta': '2026-06-14',
      'resumen': 'Semana tranquila.',
    });
    expect(r.focos, isEmpty);
    expect(r.vencidas, isEmpty);
    expect(r.completadas, 0);
  });
}
