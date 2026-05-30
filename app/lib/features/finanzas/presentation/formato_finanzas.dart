import 'package:intl/intl.dart';

final NumberFormat _montoFmt = NumberFormat('#,##0.00');

/// Formatea un monto en soles: `S/ 1,234.50`. Siempre con dos decimales.
String montoSoles(double monto) => 'S/ ${_montoFmt.format(monto.abs())}';

/// Como [montoSoles] pero con signo explícito (`+ S/ 100.00` / `− S/ 50.00`),
/// para la lista de movimientos y el balance.
String montoConSigno(double monto, {required bool esIngreso}) {
  final signo = esIngreso ? '+ ' : '− ';
  return '$signo${montoSoles(monto)}';
}
