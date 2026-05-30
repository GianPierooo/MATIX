import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/finanzas/domain/analitica_finanzas.dart';
import 'package:matix/features/finanzas/domain/movimiento.dart';

/// Tests de las agregaciones del dashboard (Finanzas-3): gastos por
/// categoría, ingresos vs gastos por mes y el corte por período.

Movimiento _mov({
  TipoMovimiento tipo = TipoMovimiento.gasto,
  double monto = 10,
  String categoria = 'General',
  required DateTime fecha,
}) =>
    Movimiento(
      id: 'm',
      tipo: tipo,
      monto: monto,
      categoria: categoria,
      fecha: fecha,
      creadoEn: fecha,
      actualizadoEn: fecha,
    );

void main() {
  group('gastosPorCategoria', () {
    test('suma solo gastos, agrupa por categoría y ordena desc', () {
      final datos = gastosPorCategoria([
        _mov(categoria: 'Comida', monto: 30, fecha: DateTime(2026, 5, 1)),
        _mov(categoria: 'Comida', monto: 20, fecha: DateTime(2026, 5, 2)),
        _mov(categoria: 'Transporte', monto: 40, fecha: DateTime(2026, 5, 3)),
        // Un ingreso no debe contar como gasto por categoría.
        _mov(
            tipo: TipoMovimiento.ingreso,
            categoria: 'Sueldo',
            monto: 1000,
            fecha: DateTime(2026, 5, 4)),
      ]);
      expect(datos.length, 2);
      // Transporte (40) va antes que Comida (50)? No: Comida=50 > Transporte=40.
      expect(datos[0].categoria, 'Comida');
      expect(datos[0].total, 50);
      expect(datos[1].categoria, 'Transporte');
      expect(datos[1].total, 40);
    });

    test('sin gastos → lista vacía', () {
      final datos = gastosPorCategoria([
        _mov(
            tipo: TipoMovimiento.ingreso,
            monto: 100,
            fecha: DateTime(2026, 5, 1)),
      ]);
      expect(datos, isEmpty);
    });
  });

  group('ingresosVsGastosPorMes', () {
    test('un bucket por mes, en orden, con meses vacíos en cero', () {
      final ahora = DateTime(2026, 5, 15);
      final serie = ingresosVsGastosPorMes(
        [
          _mov(
              tipo: TipoMovimiento.ingreso,
              monto: 1000,
              fecha: DateTime(2026, 5, 1)),
          _mov(monto: 200, fecha: DateTime(2026, 5, 20)),
          _mov(monto: 50, fecha: DateTime(2026, 3, 10)),
        ],
        ahora,
        3, // marzo, abril, mayo
      );
      expect(serie.length, 3);
      // Orden cronológico: marzo, abril, mayo.
      expect(serie[0].mes, 3);
      expect(serie[0].gastos, 50);
      expect(serie[0].ingresos, 0);
      // Abril: vacío.
      expect(serie[1].mes, 4);
      expect(serie[1].ingresos, 0);
      expect(serie[1].gastos, 0);
      // Mayo.
      expect(serie[2].mes, 5);
      expect(serie[2].ingresos, 1000);
      expect(serie[2].gastos, 200);
      expect(serie[2].balance, 800);
    });

    test('cruza el cambio de año hacia atrás', () {
      final ahora = DateTime(2026, 1, 15);
      final serie = ingresosVsGastosPorMes(
        [_mov(monto: 99, fecha: DateTime(2025, 12, 5))],
        ahora,
        3, // nov-2025, dic-2025, ene-2026
      );
      expect(serie.map((m) => '${m.anio}-${m.mes}'),
          ['2025-11', '2025-12', '2026-1']);
      expect(serie[1].gastos, 99);
    });
  });

  group('movimientosDelPeriodo', () {
    final movimientos = [
      _mov(monto: 10, fecha: DateTime(2026, 5, 10)),
      _mov(monto: 20, fecha: DateTime(2026, 4, 10)),
      _mov(monto: 30, fecha: DateTime(2026, 2, 10)),
    ];
    final ahora = DateTime(2026, 5, 15);

    test('mes actual solo trae el mes de ahora', () {
      final r = movimientosDelPeriodo(
          movimientos, ahora, PeriodoFinanzas.mesActual);
      expect(r.length, 1);
      expect(r.single.fecha.month, 5);
    });

    test('últimos 3 meses incluye marzo..mayo (excluye febrero)', () {
      final r =
          movimientosDelPeriodo(movimientos, ahora, PeriodoFinanzas.ultimos3);
      expect(r.length, 2); // mayo y abril; febrero queda fuera
      expect(r.every((m) => m.fecha.month >= 3), isTrue);
    });

    test('últimos 6 meses los incluye todos', () {
      final r =
          movimientosDelPeriodo(movimientos, ahora, PeriodoFinanzas.ultimos6);
      expect(r.length, 3);
    });
  });

  test('meses por período', () {
    expect(PeriodoFinanzas.mesActual.meses, 1);
    expect(PeriodoFinanzas.ultimos3.meses, 3);
    expect(PeriodoFinanzas.ultimos6.meses, 6);
  });
}
