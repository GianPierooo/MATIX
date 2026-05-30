import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/finanzas/domain/movimiento.dart';

/// Tests de la lógica pura de Finanzas-1: parseo del tipo, el cálculo de
/// balance/resumen, el corte por mes y las categorías sugeridas.

Movimiento _mov({
  String id = 'm',
  TipoMovimiento tipo = TipoMovimiento.gasto,
  double monto = 10,
  String categoria = 'General',
  required DateTime fecha,
  DateTime? creado,
}) =>
    Movimiento(
      id: id,
      tipo: tipo,
      monto: monto,
      categoria: categoria,
      fecha: fecha,
      creadoEn: creado ?? fecha,
      actualizadoEn: creado ?? fecha,
    );

void main() {
  group('tipo', () {
    test('parsea ingreso/gasto y cae a gasto ante lo desconocido', () {
      expect(tipoMovimientoDe('ingreso'), TipoMovimiento.ingreso);
      expect(tipoMovimientoDe('gasto'), TipoMovimiento.gasto);
      expect(tipoMovimientoDe(null), TipoMovimiento.gasto);
      expect(tipoMovimientoDe('otro'), TipoMovimiento.gasto);
    });

    test('apiValue ida y vuelta', () {
      expect(TipoMovimiento.ingreso.apiValue, 'ingreso');
      expect(TipoMovimiento.gasto.apiValue, 'gasto');
    });
  });

  test('fromJson parsea monto, fecha, tipo y nota', () {
    final m = Movimiento.fromJson({
      'id': 'abc',
      'tipo': 'ingreso',
      'monto': 1500.5,
      'categoria': 'Sueldo',
      'fecha': '2026-05-10',
      'nota': 'mayo',
      'creado_en': '2026-05-10T12:00:00Z',
      'actualizado_en': '2026-05-10T12:00:00Z',
    });
    expect(m.tipo, TipoMovimiento.ingreso);
    expect(m.monto, 1500.5);
    expect(m.categoria, 'Sueldo');
    expect(m.fecha.year, 2026);
    expect(m.fecha.month, 5);
    expect(m.fecha.day, 10);
    expect(m.nota, 'mayo');
  });

  group('resumen y balance', () {
    test('resumenDe suma ingresos y gastos y calcula balance', () {
      final r = resumenDe([
        _mov(tipo: TipoMovimiento.ingreso, monto: 1000, fecha: DateTime(2026, 5, 1)),
        _mov(tipo: TipoMovimiento.gasto, monto: 250, fecha: DateTime(2026, 5, 2)),
        _mov(tipo: TipoMovimiento.gasto, monto: 100, fecha: DateTime(2026, 5, 3)),
      ]);
      expect(r.ingresos, 1000);
      expect(r.gastos, 350);
      expect(r.balance, 650);
    });

    test('balance negativo cuando gastas de más', () {
      final r = resumenDe([
        _mov(tipo: TipoMovimiento.ingreso, monto: 100, fecha: DateTime(2026, 5, 1)),
        _mov(tipo: TipoMovimiento.gasto, monto: 300, fecha: DateTime(2026, 5, 2)),
      ]);
      expect(r.balance, -200);
    });

    test('lista vacía → resumen vacío con balance 0', () {
      final r = resumenDe(const []);
      expect(r.vacio, isTrue);
      expect(r.balance, 0);
    });
  });

  group('corte por mes', () {
    final movimientos = [
      _mov(id: 'a', tipo: TipoMovimiento.ingreso, monto: 1000, fecha: DateTime(2026, 5, 1)),
      _mov(id: 'b', tipo: TipoMovimiento.gasto, monto: 200, fecha: DateTime(2026, 5, 20)),
      _mov(id: 'c', tipo: TipoMovimiento.gasto, monto: 999, fecha: DateTime(2026, 4, 30)),
      _mov(id: 'd', tipo: TipoMovimiento.ingreso, monto: 50, fecha: DateTime(2025, 5, 15)),
    ];

    test('resumenDeMes solo cuenta el mes/año pedido', () {
      final mayo2026 = resumenDeMes(movimientos, 2026, 5);
      expect(mayo2026.ingresos, 1000);
      expect(mayo2026.gastos, 200);
      expect(mayo2026.balance, 800);
      // Abril y mayo-2025 no entran.
      expect(resumenDeMes(movimientos, 2026, 4).gastos, 999);
      expect(resumenDeMes(movimientos, 2025, 5).ingresos, 50);
    });

    test('movimientosDeMes filtra y ordena por fecha desc', () {
      final delMes = movimientosDeMes(movimientos, 2026, 5);
      expect(delMes.map((m) => m.id), ['b', 'a']); // 20 may antes que 1 may
    });

    test('mes sin movimientos → vacío', () {
      expect(movimientosDeMes(movimientos, 2026, 1), isEmpty);
      expect(resumenDeMes(movimientos, 2026, 1).vacio, isTrue);
    });
  });

  test('categoriasUsadas devuelve únicas y ordenadas', () {
    final cats = categoriasUsadas([
      _mov(categoria: 'Comida', fecha: DateTime(2026, 5, 1)),
      _mov(categoria: 'Transporte', fecha: DateTime(2026, 5, 2)),
      _mov(categoria: 'Comida', fecha: DateTime(2026, 5, 3)),
    ]);
    expect(cats, ['Comida', 'Transporte']);
  });
}
