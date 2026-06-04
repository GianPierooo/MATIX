import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/proyectos/domain/proyecto.dart';

/// El % de avance lo calcula el cerebro (ponderado por fase) y viaja en el JSON
/// del proyecto. La app solo lo parsea y lo pinta. Aquí verificamos el parseo.

Map<String, dynamic> _base() => {
      'id': 'p1',
      'nombre': 'Tesis',
      'estado': 'activo',
      'ultima_actividad_en': '2026-06-03T12:00:00Z',
      'creado_en': '2026-06-01T12:00:00Z',
      'actualizado_en': '2026-06-03T12:00:00Z',
    };

void main() {
  test('parsea avance cuando viene', () {
    final p = Proyecto.fromJson({..._base(), 'avance': 42});
    expect(p.avance, 42);
  });

  test('avance null cuando el proyecto no tiene plan (campo ausente o null)', () {
    expect(Proyecto.fromJson(_base()).avance, isNull);
    expect(Proyecto.fromJson({..._base(), 'avance': null}).avance, isNull);
  });
}
