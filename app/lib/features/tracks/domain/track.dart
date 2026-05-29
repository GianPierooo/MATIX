import 'package:flutter/foundation.dart';

/// Estado de un track de aprendizaje. Son CONTINUOS: no se terminan,
/// solo se pausan.
enum EstadoTrack {
  activo,
  pausado;

  static EstadoTrack fromJson(String? s) =>
      s == 'pausado' ? EstadoTrack.pausado : EstadoTrack.activo;

  String toJson() => name;

  String get label => switch (this) {
        EstadoTrack.activo => 'Activo',
        EstadoTrack.pausado => 'En pausa',
      };
}

/// Un track de aprendizaje (Fase 2): una skill que se aprende de forma
/// continua (inglés, calistenia, guitarra…), con su posición (en qué
/// bloque va) y su estado.
@immutable
class Track {
  const Track({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.estado = EstadoTrack.activo,
    this.bloqueActual,
    this.semana,
    this.dia,
    required this.creadoEn,
    required this.actualizadoEn,
  });

  final String id;
  final String nombre;
  final String? descripcion;
  final EstadoTrack estado;
  final String? bloqueActual;
  final int? semana;
  final int? dia;
  final DateTime creadoEn;
  final DateTime actualizadoEn;

  bool get activo => estado == EstadoTrack.activo;

  /// Posición legible: "Bloque 3 · semana 2 · día 4" / "Sin posición".
  String get posicionLabel {
    final partes = <String>[];
    if (bloqueActual != null && bloqueActual!.trim().isNotEmpty) {
      partes.add(bloqueActual!.trim());
    }
    if (semana != null) partes.add('semana $semana');
    if (dia != null) partes.add('día $dia');
    return partes.isEmpty ? 'Sin posición' : partes.join(' · ');
  }

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        descripcion: j['descripcion'] as String?,
        estado: EstadoTrack.fromJson(j['estado'] as String?),
        bloqueActual: j['bloque_actual'] as String?,
        semana: (j['semana'] as num?)?.toInt(),
        dia: (j['dia'] as num?)?.toInt(),
        creadoEn: DateTime.parse(j['creado_en'] as String),
        actualizadoEn: DateTime.parse(j['actualizado_en'] as String),
      );
}

/// Los tracks activos (los que tienen presión / foco).
List<Track> tracksActivos(List<Track> todos) =>
    todos.where((t) => t.activo).toList();

/// Los tracks en pausa (sin presión).
List<Track> tracksPausados(List<Track> todos) =>
    todos.where((t) => !t.activo).toList();

/// Tope de tracks activos a la vez (igual que la regla de los 3
/// proyectos). El cerebro es la autoridad; esto es para la UI.
const int kTopeTracksActivos = 3;

/// ¿Se puede activar otro track, o ya está en el tope?
bool puedeActivarOtro(List<Track> todos) =>
    tracksActivos(todos).length < kTopeTracksActivos;
