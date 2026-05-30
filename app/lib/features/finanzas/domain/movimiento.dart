import 'package:flutter/foundation.dart';

/// Tipo de un movimiento: un ingreso suma al balance, un gasto resta.
/// El signo lo da el tipo; el monto siempre es positivo.
enum TipoMovimiento { ingreso, gasto }

TipoMovimiento tipoMovimientoDe(String? s) =>
    s == 'ingreso' ? TipoMovimiento.ingreso : TipoMovimiento.gasto;

extension TipoMovimientoX on TipoMovimiento {
  String get apiValue => this == TipoMovimiento.ingreso ? 'ingreso' : 'gasto';
  String get label => this == TipoMovimiento.ingreso ? 'Ingreso' : 'Gasto';
  bool get esIngreso => this == TipoMovimiento.ingreso;
}

/// Un movimiento de finanzas (Finanzas-1): ingreso o gasto, con monto,
/// categoría, fecha y una nota opcional. La imagen del recibo y el
/// dashboard con gráficos vienen en Finanzas-2/3.
@immutable
class Movimiento {
  const Movimiento({
    required this.id,
    required this.tipo,
    required this.monto,
    required this.categoria,
    required this.fecha,
    this.nota = '',
    required this.creadoEn,
    required this.actualizadoEn,
  });

  final String id;
  final TipoMovimiento tipo;
  final double monto;
  final String categoria;

  /// Día del movimiento (sin hora). El corte de finanzas es por mes.
  final DateTime fecha;
  final String nota;
  final DateTime creadoEn;
  final DateTime actualizadoEn;

  factory Movimiento.fromJson(Map<String, dynamic> j) => Movimiento(
        id: j['id'] as String,
        tipo: tipoMovimientoDe(j['tipo'] as String?),
        monto: (j['monto'] as num).toDouble(),
        categoria: j['categoria'] as String? ?? 'General',
        fecha: DateTime.parse(j['fecha'] as String),
        nota: j['nota'] as String? ?? '',
        creadoEn: DateTime.parse(j['creado_en'] as String),
        actualizadoEn: DateTime.parse(j['actualizado_en'] as String),
      );
}

/// Resumen de un conjunto de movimientos: totales y balance. Inmutable y
/// puro — la base del corte por mes y de la tarjeta de Inicio.
@immutable
class ResumenFinanzas {
  const ResumenFinanzas({this.ingresos = 0, this.gastos = 0});

  final double ingresos;
  final double gastos;

  /// Ingresos menos gastos. Positivo = te sobró; negativo = gastaste de más.
  double get balance => ingresos - gastos;
  bool get vacio => ingresos == 0 && gastos == 0;
}

/// Suma ingresos y gastos de una lista de movimientos (cualquiera).
ResumenFinanzas resumenDe(Iterable<Movimiento> movimientos) {
  var ingresos = 0.0;
  var gastos = 0.0;
  for (final m in movimientos) {
    if (m.tipo == TipoMovimiento.ingreso) {
      ingresos += m.monto;
    } else {
      gastos += m.monto;
    }
  }
  return ResumenFinanzas(ingresos: ingresos, gastos: gastos);
}

/// Los movimientos de un mes concreto ([anio], [mes] 1-12), ordenados por
/// fecha descendente y, a igual fecha, por creación descendente.
List<Movimiento> movimientosDeMes(
  List<Movimiento> todos,
  int anio,
  int mes,
) {
  final out = todos
      .where((m) => m.fecha.year == anio && m.fecha.month == mes)
      .toList()
    ..sort((a, b) {
      final c = b.fecha.compareTo(a.fecha);
      if (c != 0) return c;
      return b.creadoEn.compareTo(a.creadoEn);
    });
  return out;
}

/// El resumen (ingresos, gastos, balance) de un mes concreto.
ResumenFinanzas resumenDeMes(List<Movimiento> todos, int anio, int mes) =>
    resumenDe(todos.where((m) => m.fecha.year == anio && m.fecha.month == mes));

/// Categorías ya usadas, sin repetir y ordenadas, para sugerirlas en el
/// formulario (categorías simples editables).
List<String> categoriasUsadas(List<Movimiento> todos) {
  final set = <String>{
    for (final m in todos)
      if (m.categoria.trim().isNotEmpty) m.categoria.trim(),
  };
  final out = set.toList()..sort();
  return out;
}
