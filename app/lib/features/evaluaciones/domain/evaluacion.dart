import 'package:flutter/foundation.dart';

enum TipoEvaluacion {
  entrega,
  examen,
  proyecto,
  otro;

  static TipoEvaluacion fromJson(String s) => switch (s) {
        'examen' => TipoEvaluacion.examen,
        'proyecto' => TipoEvaluacion.proyecto,
        'otro' => TipoEvaluacion.otro,
        _ => TipoEvaluacion.entrega,
      };

  String toJson() => name;

  String get label => switch (this) {
        TipoEvaluacion.entrega => 'Entrega',
        TipoEvaluacion.examen => 'Examen',
        TipoEvaluacion.proyecto => 'Proyecto',
        TipoEvaluacion.otro => 'Otro',
      };
}

@immutable
class Evaluacion {
  const Evaluacion({
    required this.id,
    required this.cursoId,
    required this.titulo,
    required this.tipo,
    required this.fecha,
    this.descripcion,
    this.peso,
    this.notaObtenida,
    this.notaMaxima,
    this.recordarEn,
    required this.creadaEn,
    required this.actualizadaEn,
  });

  final String id;
  final String cursoId;
  final String titulo;
  final TipoEvaluacion tipo;
  final DateTime fecha;
  final String? descripcion;
  final double? peso;
  final double? notaObtenida;
  final double? notaMaxima;
  final DateTime? recordarEn;
  final DateTime creadaEn;
  final DateTime actualizadaEn;

  bool get tieneNota => notaObtenida != null;

  factory Evaluacion.fromJson(Map<String, dynamic> j) => Evaluacion(
        id: j['id'] as String,
        cursoId: j['curso_id'] as String,
        titulo: j['titulo'] as String,
        tipo: TipoEvaluacion.fromJson(j['tipo'] as String),
        fecha: DateTime.parse(j['fecha'] as String),
        descripcion: j['descripcion'] as String?,
        peso: (j['peso'] as num?)?.toDouble(),
        notaObtenida: (j['nota_obtenida'] as num?)?.toDouble(),
        notaMaxima: (j['nota_maxima'] as num?)?.toDouble(),
        recordarEn: j['recordar_en'] == null
            ? null
            : DateTime.parse(j['recordar_en'] as String),
        creadaEn: DateTime.parse(j['creada_en'] as String),
        actualizadaEn: DateTime.parse(j['actualizada_en'] as String),
      );
}
