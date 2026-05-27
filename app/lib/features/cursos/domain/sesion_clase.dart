import 'package:flutter/foundation.dart';

/// Horario recurrente de una clase: día de la semana + bloque horario.
/// `diaSemana` 0=lunes … 6=domingo (compatible con DateTime.weekday-1).
@immutable
class SesionClase {
  const SesionClase({
    required this.id,
    required this.cursoId,
    required this.diaSemana,
    required this.horaInicio, // "HH:MM:SS"
    required this.horaFin,
    this.ubicacion,
  });

  final String id;
  final String cursoId;
  final int diaSemana;
  final String horaInicio;
  final String horaFin;
  final String? ubicacion;

  /// `true` si la sesión ocurre el día `d` (semana civil L=0).
  bool ocurreEn(DateTime d) => (d.weekday - 1) == diaSemana;

  /// Hora inicio como DateTime sobre el día `d`.
  DateTime inicioEn(DateTime d) {
    final parts = horaInicio.split(':');
    return DateTime(d.year, d.month, d.day,
        int.parse(parts[0]), int.parse(parts[1]));
  }

  DateTime finEn(DateTime d) {
    final parts = horaFin.split(':');
    return DateTime(d.year, d.month, d.day,
        int.parse(parts[0]), int.parse(parts[1]));
  }

  factory SesionClase.fromJson(Map<String, dynamic> j) => SesionClase(
        id: j['id'] as String,
        cursoId: j['curso_id'] as String,
        diaSemana: j['dia_semana'] as int,
        horaInicio: j['hora_inicio'] as String,
        horaFin: j['hora_fin'] as String,
        ubicacion: j['ubicacion'] as String?,
      );
}
