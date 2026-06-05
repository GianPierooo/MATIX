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
    this.bloqueInicio,
    this.bloqueFin,
    this.nudgesSilenciada = false,
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

  /// Urgencia-3: bloque de tiempo asignado al planificar el día.
  /// `bloqueInicio` cuándo empezarla; `bloqueFin` cuándo debería estar
  /// hecha. No pisan `venceEn` (el plazo real de entrega).
  final DateTime? bloqueInicio;
  final DateTime? bloqueFin;

  /// Push Capa 3b: si está en `true`, el cerebro NO manda nudges de
  /// urgencia para esta tarea (apagado por tarea). El maestro global
  /// vive en Ajustes.
  final bool nudgesSilenciada;

  /// El plazo que manda para la urgencia: el bloque planificado si lo
  /// hay (es un "plazo propio"), si no el vencimiento real. Lo usan los
  /// contadores (Urgencia-1) y los nudges (Urgencia-2).
  DateTime? get plazoEfectivo => bloqueFin ?? venceEn;

  /// `true` si la tarea está AGENDADA en una hora concreta (tiene bloque del
  /// plan del día). Es distinto de tener `venceEn` (plazo de entrega): una
  /// tarea agendada se ve como bloque en "Tu día" y en la pestaña Tareas se
  /// muestra con el chip de hora del bloque.
  bool get estaAgendada => bloqueInicio != null;

  /// `true` si está en el BACKLOG: sin plazo real, sin bloque agendado, y
  /// no completada. Antes morían en silencio; ahora se ven como "Sin fecha"
  /// y el planificador las ofrece en huecos cuando hay espacio.
  bool get esBacklog =>
      !completada && venceEn == null && bloqueInicio == null;

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
        bloqueInicio: _parseTs(json['bloque_inicio']),
        bloqueFin: _parseTs(json['bloque_fin']),
        nudgesSilenciada: json['nudges_silenciada'] as bool? ?? false,
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
