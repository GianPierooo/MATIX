import 'package:flutter/foundation.dart';

/// Un gasto candidato que el cerebro extrajo del texto de un recibo
/// (Finanzas-2). Es editable en la hoja de revisión antes de guardarse
/// como movimiento (gasto) en Finanzas. Nada se crea hasta confirmar.
///
/// Todo es opcional: si el OCR no dio un total claro, [monto] viene
/// `null` y la app deja escribirlo a mano — no se inventan cifras.
@immutable
class ReciboPropuesto {
  const ReciboPropuesto({
    this.monto,
    this.fecha,
    this.comercio,
    this.categoria,
  });

  final double? monto;
  final DateTime? fecha;
  final String? comercio;
  final String? categoria;

  /// Parse del JSON del cerebro (`{monto, fecha, comercio, categoria}`).
  /// `fecha` llega como `YYYY-MM-DD` o `null`; si es inválida la
  /// descartamos en vez de reventar. `monto` puede venir como número o
  /// (por robustez) como string; si no es un positivo claro, queda null.
  factory ReciboPropuesto.fromCerebro(Map<String, dynamic> j) {
    final montoCrudo = j['monto'];
    double? monto;
    if (montoCrudo is num) {
      monto = montoCrudo.toDouble();
    } else if (montoCrudo is String) {
      monto = double.tryParse(montoCrudo.replaceAll(',', '').trim());
    }
    if (monto != null && monto <= 0) monto = null;

    final fechaCruda = j['fecha'] as String?;
    DateTime? fecha;
    if (fechaCruda != null && fechaCruda.trim().isNotEmpty) {
      fecha = DateTime.tryParse(fechaCruda.trim());
    }

    String? texto(Object? v) =>
        v is String && v.trim().isNotEmpty ? v.trim() : null;

    return ReciboPropuesto(
      monto: monto,
      fecha: fecha,
      comercio: texto(j['comercio']),
      categoria: texto(j['categoria']),
    );
  }
}
