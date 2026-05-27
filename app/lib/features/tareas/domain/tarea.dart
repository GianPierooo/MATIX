import 'package:flutter/foundation.dart';

enum Prioridad {
  alta,
  media,
  baja;

  static Prioridad fromJson(String s) => switch (s) {
        'alta' => Prioridad.alta,
        'baja' => Prioridad.baja,
        _ => Prioridad.media,
      };

  String toJson() => name;

  String get label => switch (this) {
        Prioridad.alta => 'Alta',
        Prioridad.media => 'Media',
        Prioridad.baja => 'Baja',
      };
}

enum Repeticion {
  diaria,
  semanal,
  mensual,
  anual;

  static Repeticion? fromJsonOrNull(String? s) => switch (s) {
        'diaria' => Repeticion.diaria,
        'semanal' => Repeticion.semanal,
        'mensual' => Repeticion.mensual,
        'anual' => Repeticion.anual,
        _ => null,
      };

  String toJson() => name;

  String get label => switch (this) {
        Repeticion.diaria => 'Diaria',
        Repeticion.semanal => 'Semanal',
        Repeticion.mensual => 'Mensual',
        Repeticion.anual => 'Anual',
      };
}

@immutable
class Tarea {
  const Tarea({
    required this.id,
    required this.titulo,
    this.nota,
    this.venceEn,
    this.prioridad = Prioridad.media,
    this.categoriaId,
    this.cursoId,
    this.proyectoId,
    this.repeticion,
    this.recordarEn,
    this.completada = false,
    this.completadaEn,
    required this.creadaEn,
    required this.actualizadaEn,
  });

  final String id;
  final String titulo;
  final String? nota;
  final DateTime? venceEn;
  final Prioridad prioridad;
  final String? categoriaId;
  final String? cursoId;
  final String? proyectoId;
  final Repeticion? repeticion;
  final DateTime? recordarEn;
  final bool completada;
  final DateTime? completadaEn;
  final DateTime creadaEn;
  final DateTime actualizadaEn;

  /// `true` si tiene fecha de vencimiento y ya pasó (y no está completada).
  bool get estaVencida =>
      !completada &&
      venceEn != null &&
      venceEn!.isBefore(DateTime.now());

  /// `true` si vence hoy (entre 00:00 y 23:59 de hoy local).
  bool venceHoy(DateTime ahora) {
    final v = venceEn;
    if (v == null) return false;
    final local = v.toLocal();
    return local.year == ahora.year &&
        local.month == ahora.month &&
        local.day == ahora.day;
  }

  factory Tarea.fromJson(Map<String, dynamic> json) => Tarea(
        id: json['id'] as String,
        titulo: json['titulo'] as String,
        nota: json['nota'] as String?,
        venceEn: _parseTs(json['vence_en']),
        prioridad: Prioridad.fromJson(json['prioridad'] as String),
        categoriaId: json['categoria_id'] as String?,
        cursoId: json['curso_id'] as String?,
        proyectoId: json['proyecto_id'] as String?,
        repeticion: Repeticion.fromJsonOrNull(json['repeticion'] as String?),
        recordarEn: _parseTs(json['recordar_en']),
        completada: json['completada'] as bool,
        completadaEn: _parseTs(json['completada_en']),
        creadaEn: DateTime.parse(json['creada_en'] as String),
        actualizadaEn: DateTime.parse(json['actualizada_en'] as String),
      );
}

DateTime? _parseTs(dynamic v) =>
    v == null ? null : DateTime.parse(v as String);

@immutable
class Subtarea {
  const Subtarea({
    required this.id,
    required this.tareaId,
    required this.titulo,
    this.completada = false,
    this.orden = 0,
    required this.creadaEn,
  });

  final String id;
  final String tareaId;
  final String titulo;
  final bool completada;
  final int orden;
  final DateTime creadaEn;

  factory Subtarea.fromJson(Map<String, dynamic> json) => Subtarea(
        id: json['id'] as String,
        tareaId: json['tarea_id'] as String,
        titulo: json['titulo'] as String,
        completada: json['completada'] as bool,
        orden: json['orden'] as int,
        creadaEn: DateTime.parse(json['creada_en'] as String),
      );
}
