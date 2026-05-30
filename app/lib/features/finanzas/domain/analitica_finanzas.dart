import 'package:flutter/foundation.dart';

import 'movimiento.dart';

/// Período del dashboard de Finanzas (Finanzas-3). Solo visualización
/// sobre los movimientos ya registrados.
enum PeriodoFinanzas { mesActual, ultimos3, ultimos6 }

extension PeriodoFinanzasX on PeriodoFinanzas {
  /// Cuántos meses abarca el período (incluyendo el mes actual).
  int get meses => switch (this) {
        PeriodoFinanzas.mesActual => 1,
        PeriodoFinanzas.ultimos3 => 3,
        PeriodoFinanzas.ultimos6 => 6,
      };

  String get label => switch (this) {
        PeriodoFinanzas.mesActual => 'Este mes',
        PeriodoFinanzas.ultimos3 => '3 meses',
        PeriodoFinanzas.ultimos6 => '6 meses',
      };
}

/// Clave ordenable de un mes (año·12 + mes), para comparar meses sin
/// líos de fechas.
int _claveMes(int anio, int mes) => anio * 12 + (mes - 1);

/// Los movimientos dentro del período que termina en [ahora] y abarca
/// `periodo.meses` meses (incluido el mes de [ahora]).
List<Movimiento> movimientosDelPeriodo(
  List<Movimiento> todos,
  DateTime ahora,
  PeriodoFinanzas periodo,
) {
  final finK = _claveMes(ahora.year, ahora.month);
  final iniK = finK - (periodo.meses - 1);
  return todos.where((m) {
    final k = _claveMes(m.fecha.year, m.fecha.month);
    return k >= iniK && k <= finK;
  }).toList();
}

/// Gasto total acumulado en una categoría.
@immutable
class CategoriaTotal {
  const CategoriaTotal(this.categoria, this.total);
  final String categoria;
  final double total;
}

/// Suma los GASTOS por categoría (ignora ingresos), de mayor a menor.
/// Para ver en qué se te va la plata.
List<CategoriaTotal> gastosPorCategoria(Iterable<Movimiento> movimientos) {
  final mapa = <String, double>{};
  for (final m in movimientos) {
    if (m.tipo != TipoMovimiento.gasto) continue;
    final cat = m.categoria.trim().isEmpty ? 'Otros' : m.categoria.trim();
    mapa[cat] = (mapa[cat] ?? 0) + m.monto;
  }
  final out = mapa.entries
      .map((e) => CategoriaTotal(e.key, e.value))
      .toList()
    ..sort((a, b) {
      final c = b.total.compareTo(a.total);
      return c != 0 ? c : a.categoria.compareTo(b.categoria);
    });
  return out;
}

/// Totales de un mes concreto, para la serie temporal.
@immutable
class MesTotales {
  const MesTotales({
    required this.anio,
    required this.mes,
    required this.ingresos,
    required this.gastos,
  });
  final int anio;
  final int mes;
  final double ingresos;
  final double gastos;
  double get balance => ingresos - gastos;
}

/// Ingresos y gastos por mes: un bucket por cada mes del período que
/// termina en [ahora] y abarca [meses] meses, en orden cronológico. Los
/// meses sin movimientos quedan en cero (para que la serie no tenga
/// huecos).
List<MesTotales> ingresosVsGastosPorMes(
  List<Movimiento> todos,
  DateTime ahora,
  int meses,
) {
  final buckets = <int, MesTotales>{};
  final orden = <int>[];
  for (var i = meses - 1; i >= 0; i--) {
    final d = DateTime(ahora.year, ahora.month - i);
    final k = _claveMes(d.year, d.month);
    orden.add(k);
    buckets[k] =
        MesTotales(anio: d.year, mes: d.month, ingresos: 0, gastos: 0);
  }
  for (final m in todos) {
    final k = _claveMes(m.fecha.year, m.fecha.month);
    final b = buckets[k];
    if (b == null) continue; // fuera del período
    buckets[k] = MesTotales(
      anio: b.anio,
      mes: b.mes,
      ingresos:
          b.ingresos + (m.tipo == TipoMovimiento.ingreso ? m.monto : 0.0),
      gastos: b.gastos + (m.tipo == TipoMovimiento.gasto ? m.monto : 0.0),
    );
  }
  return [for (final k in orden) buckets[k]!];
}
