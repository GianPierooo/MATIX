import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/proyectos/domain/proyecto.dart';

/// Parseo de la descomposición (árbol) del proyecto.
void main() {
  group('NodoArbol.fromJson', () {
    test('fase raíz (fino) y paso hijo', () {
      final fase = NodoArbol.fromJson({
        'id': 'f1',
        'parent_id': null,
        'titulo': 'Sprint a la primera venta',
        'fase': 'Sprint a la primera venta',
        'granularidad': 'fino',
        'estado': 'pendiente',
        'orden': 0,
      });
      expect(fase.esRaiz, isTrue);
      expect(fase.grueso, isFalse);
      expect(fase.hecho, isFalse);

      final paso = NodoArbol.fromJson({
        'id': 'n1',
        'parent_id': 'f1',
        'titulo': 'Calcular el costo real',
        'granularidad': 'fino',
        'estado': 'hecho',
        'orden': 2,
        'tarea_id': 't9',
      });
      expect(paso.esRaiz, isFalse);
      expect(paso.parentId, 'f1');
      expect(paso.hecho, isTrue);
      expect(paso.tareaId, 't9');
    });

    test('fase gruesa (por desglosar)', () {
      final g = NodoArbol.fromJson({
        'id': 'f2',
        'parent_id': null,
        'titulo': 'Mediano plazo',
        'granularidad': 'grueso',
        'estado': 'pendiente',
        'orden': 1,
        'notas': 'Por desglosar: a; b; c',
      });
      expect(g.grueso, isTrue);
      expect(g.esRaiz, isTrue);
      expect(g.notas, contains('Por desglosar'));
    });

    test('defaults tolerantes', () {
      final n = NodoArbol.fromJson({'id': 'x'});
      expect(n.titulo, '');
      expect(n.granularidad, 'fino');
      expect(n.estado, 'pendiente');
      expect(n.orden, 0);
    });
  });
}
