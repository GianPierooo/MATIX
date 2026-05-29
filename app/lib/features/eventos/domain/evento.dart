import 'package:flutter/foundation.dart';

@immutable
class Evento {
  const Evento({
    required this.id,
    required this.titulo,
    this.descripcion,
    required this.iniciaEn,
    this.terminaEn,
    this.todoElDia = false,
    this.ubicacion,
    this.cursoId,
    this.proyectoId,
    this.color,
    this.recordarEn,
    this.origen = 'manual',
    this.externalId,
    this.googleUpdatedAt,
    required this.creadoEn,
    required this.actualizadoEn,
  });

  final String id;
  final String titulo;
  final String? descripcion;
  final DateTime iniciaEn;
  final DateTime? terminaEn;
  final bool todoElDia;
  final String? ubicacion;
  final String? cursoId;
  final String? proyectoId;
  final String? color;
  final DateTime? recordarEn;
  /// "manual" para los creados desde la app, "google" para los
  /// sincronizados desde Google Calendar (Capa 4 Paso 1). La UI
  /// muestra un badge sutil para distinguirlos.
  final String origen;
  /// Capa 4 Paso 2: id del evento en Google Calendar (si fue
  /// empujado o si vino del pull). NULL para manuales que aún no
  /// llegaron a Google.
  final String? externalId;
  /// Capa 4 Paso 2: último timestamp conocido del lado Google.
  /// La UI puede pintar "Sincronizado · hace X" usando este valor.
  final DateTime? googleUpdatedAt;
  final DateTime creadoEn;
  final DateTime actualizadoEn;

  bool get esDeGoogle => origen == 'google';

  /// `true` cuando el evento existe a ambos lados (hub + Google).
  /// Vale para manuales pusheados y para todos los `origen='google'`.
  bool get estaSincronizado => externalId != null;

  bool ocurreEn(DateTime dia) {
    final ini = iniciaEn.toLocal();
    final iniDia = DateTime(ini.year, ini.month, ini.day);
    final esteDia = DateTime(dia.year, dia.month, dia.day);
    return iniDia.isAtSameMomentAs(esteDia);
  }

  factory Evento.fromJson(Map<String, dynamic> json) => Evento(
        id: json['id'] as String,
        titulo: json['titulo'] as String,
        descripcion: json['descripcion'] as String?,
        iniciaEn: DateTime.parse(json['inicia_en'] as String),
        terminaEn: json['termina_en'] == null
            ? null
            : DateTime.parse(json['termina_en'] as String),
        todoElDia: json['todo_el_dia'] as bool? ?? false,
        ubicacion: json['ubicacion'] as String?,
        cursoId: json['curso_id'] as String?,
        proyectoId: json['proyecto_id'] as String?,
        color: json['color'] as String?,
        recordarEn: json['recordar_en'] == null
            ? null
            : DateTime.parse(json['recordar_en'] as String),
        origen: (json['origen'] as String?) ?? 'manual',
        externalId: json['external_id'] as String?,
        googleUpdatedAt: json['google_updated_at'] == null
            ? null
            : DateTime.parse(json['google_updated_at'] as String),
        creadoEn: DateTime.parse(json['creado_en'] as String),
        actualizadoEn: DateTime.parse(json['actualizado_en'] as String),
      );
}
