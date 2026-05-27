import 'package:flutter/foundation.dart';

@immutable
class CierreDia {
  const CierreDia({
    required this.id,
    required this.fecha,
    this.items = const [],
    this.notaExtra,
    required this.creadoEn,
  });

  final String id;
  final DateTime fecha;
  final List<String> items;
  final String? notaExtra;
  final DateTime creadoEn;

  factory CierreDia.fromJson(Map<String, dynamic> j) => CierreDia(
        id: j['id'] as String,
        fecha: DateTime.parse(j['fecha'] as String),
        items: (j['items'] as List?)?.cast<String>() ?? const <String>[],
        notaExtra: j['nota_extra'] as String?,
        creadoEn: DateTime.parse(j['creado_en'] as String),
      );
}
