import 'package:flutter/foundation.dart';

@immutable
class Curso {
  const Curso({
    required this.id,
    required this.nombre,
    this.profesor,
    this.color,
    required this.creadoEn,
    required this.actualizadoEn,
  });

  final String id;
  final String nombre;
  final String? profesor;
  final String? color;
  final DateTime creadoEn;
  final DateTime actualizadoEn;

  factory Curso.fromJson(Map<String, dynamic> j) => Curso(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        profesor: j['profesor'] as String?,
        color: j['color'] as String?,
        creadoEn: DateTime.parse(j['creado_en'] as String),
        actualizadoEn: DateTime.parse(j['actualizado_en'] as String),
      );
}
