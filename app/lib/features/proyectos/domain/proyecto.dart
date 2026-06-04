import 'package:flutter/foundation.dart';

enum EstadoProyecto {
  activo,
  aparcado,
  terminado;

  static EstadoProyecto fromJson(String s) => switch (s) {
        'aparcado' => EstadoProyecto.aparcado,
        'terminado' => EstadoProyecto.terminado,
        _ => EstadoProyecto.activo,
      };

  String toJson() => name;

  String get label => switch (this) {
        EstadoProyecto.activo => 'Activo',
        EstadoProyecto.aparcado => 'Aparcado',
        EstadoProyecto.terminado => 'Terminado',
      };
}

@immutable
class Proyecto {
  const Proyecto({
    required this.id,
    required this.nombre,
    this.descripcion,
    required this.estado,
    this.prioridad,
    this.lineaMeta,
    this.tareaSiguienteId,
    required this.ultimaActividadEn,
    this.bloqueProtegido,
    this.color,
    this.inactivoDesde,
    required this.creadoEn,
    required this.actualizadoEn,
    this.avance,
  });

  final String id;
  final String nombre;
  final String? descripcion;
  final EstadoProyecto estado;
  final int? prioridad;
  final String? lineaMeta;
  final String? tareaSiguienteId;
  final DateTime ultimaActividadEn;
  final Map<String, dynamic>? bloqueProtegido;
  final String? color;
  final DateTime? inactivoDesde;
  final DateTime creadoEn;
  final DateTime actualizadoEn;

  /// % de avance (0..100) calculado desde el árbol del proyecto, o `null` si
  /// el proyecto no tiene plan todavía (no se muestra barra).
  final int? avance;

  bool get esActivo => estado == EstadoProyecto.activo;

  /// "En riesgo" si lleva 3+ días sin actividad y está activo.
  bool get enRiesgo {
    if (!esActivo) return false;
    final dias = DateTime.now().difference(ultimaActividadEn).inDays;
    return dias >= 3;
  }

  /// Texto humano del calor.
  String get etiquetaCalor {
    final ahora = DateTime.now();
    final dias = ahora.difference(ultimaActividadEn).inDays;
    if (dias <= 0) return 'Hoy';
    if (dias == 1) return 'Ayer';
    if (dias < 7) return 'Hace ${dias}d';
    if (dias < 30) return 'Hace ${(dias / 7).floor()}sem';
    return 'Hace ${(dias / 30).floor()}m';
  }

  factory Proyecto.fromJson(Map<String, dynamic> json) => Proyecto(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        descripcion: json['descripcion'] as String?,
        estado: EstadoProyecto.fromJson(json['estado'] as String),
        prioridad: json['prioridad'] as int?,
        lineaMeta: json['linea_meta'] as String?,
        tareaSiguienteId: json['tarea_siguiente_id'] as String?,
        ultimaActividadEn: DateTime.parse(json['ultima_actividad_en'] as String),
        bloqueProtegido: json['bloque_protegido'] as Map<String, dynamic>?,
        color: json['color'] as String?,
        inactivoDesde: json['inactivo_desde'] == null
            ? null
            : DateTime.parse(json['inactivo_desde'] as String),
        creadoEn: DateTime.parse(json['creado_en'] as String),
        actualizadoEn: DateTime.parse(json['actualizado_en'] as String),
        avance: json['avance'] as int?,
      );
}
