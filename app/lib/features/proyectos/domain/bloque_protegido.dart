/// Parser y formateador del `bloque_protegido` (JSONB en BD).
///
/// Shape esperado:
/// ```json
/// {
///   "dias_semana": [0, 2, 4],  // 0=Lun … 6=Dom
///   "hora_inicio": "06:00",
///   "hora_fin": "09:00"
/// }
/// ```
///
/// Si el JSON tiene otra estructura o le faltan campos, `parse`
/// devuelve `null` y la UI no muestra nada (no rompe).
class BloqueProtegido {
  const BloqueProtegido({
    required this.diasSemana,
    required this.horaInicio,
    required this.horaFin,
  });

  /// 0=Lun … 6=Dom.
  final List<int> diasSemana;
  final String horaInicio; // "HH:MM"
  final String horaFin;

  static BloqueProtegido? parse(Map<String, dynamic>? json) {
    if (json == null) return null;
    final dias = json['dias_semana'];
    final hi = json['hora_inicio'];
    final hf = json['hora_fin'];
    if (dias is! List || hi is! String || hf is! String) return null;
    final diasInt = <int>[];
    for (final d in dias) {
      if (d is int && d >= 0 && d <= 6) diasInt.add(d);
    }
    if (diasInt.isEmpty) return null;
    return BloqueProtegido(
      diasSemana: diasInt,
      horaInicio: hi,
      horaFin: hf,
    );
  }

  /// "L / Mi / V · 06:00 – 09:00"
  String legible() {
    const nombres = ['L', 'Ma', 'Mi', 'J', 'V', 'S', 'D'];
    final dias = ([...diasSemana]..sort())
        .map((d) => nombres[d])
        .join(' / ');
    return '$dias  ·  $horaInicio – $horaFin';
  }
}
