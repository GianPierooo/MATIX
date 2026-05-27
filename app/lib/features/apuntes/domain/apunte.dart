import 'package:flutter/foundation.dart';

@immutable
class Apunte {
  const Apunte({
    required this.id,
    required this.titulo,
    this.contenido = '',
    this.cuadernoId,
    this.cursoId,
    this.proyectoId,
    this.etiquetas = const [],
    required this.creadoEn,
    required this.actualizadoEn,
  });

  final String id;
  final String titulo;
  final String contenido;
  final String? cuadernoId;
  final String? cursoId;
  final String? proyectoId;
  final List<String> etiquetas;
  final DateTime creadoEn;
  final DateTime actualizadoEn;

  factory Apunte.fromJson(Map<String, dynamic> j) => Apunte(
        id: j['id'] as String,
        titulo: j['titulo'] as String,
        contenido: j['contenido'] as String? ?? '',
        cuadernoId: j['cuaderno_id'] as String?,
        cursoId: j['curso_id'] as String?,
        proyectoId: j['proyecto_id'] as String?,
        etiquetas:
            (j['etiquetas'] as List?)?.cast<String>() ?? const <String>[],
        creadoEn: DateTime.parse(j['creado_en'] as String),
        actualizadoEn: DateTime.parse(j['actualizado_en'] as String),
      );
}
