import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/captura_camara/domain/recibo_propuesto.dart';

/// Tests del parseo del gasto propuesto desde el JSON del cerebro
/// (Finanzas-2): extracción de monto/fecha/comercio/categoría y el caso
/// "sin monto claro" (null, sin inventar cifras).

void main() {
  test('fromCerebro parsea monto, fecha, comercio y categoría', () {
    final r = ReciboPropuesto.fromCerebro({
      'monto': 45.90,
      'fecha': '2026-05-10',
      'comercio': 'Supermercado XYZ',
      'categoria': 'Comida',
    });
    expect(r.monto, 45.90);
    expect(r.fecha, DateTime(2026, 5, 10));
    expect(r.comercio, 'Supermercado XYZ');
    expect(r.categoria, 'Comida');
  });

  test('monto null se mantiene null (no inventa)', () {
    final r = ReciboPropuesto.fromCerebro({
      'monto': null,
      'fecha': null,
      'comercio': 'Tienda borrosa',
      'categoria': null,
    });
    expect(r.monto, isNull);
    expect(r.fecha, isNull);
    expect(r.comercio, 'Tienda borrosa');
    expect(r.categoria, isNull);
  });

  test('monto como string numérico se parsea; <= 0 cae a null', () {
    expect(ReciboPropuesto.fromCerebro({'monto': '12.50'}).monto, 12.50);
    expect(ReciboPropuesto.fromCerebro({'monto': '0'}).monto, isNull);
    expect(ReciboPropuesto.fromCerebro({'monto': 'abc'}).monto, isNull);
  });

  test('fecha inválida se descarta sin reventar', () {
    final r = ReciboPropuesto.fromCerebro({'monto': 10, 'fecha': 'ayer'});
    expect(r.monto, 10);
    expect(r.fecha, isNull);
  });
}
