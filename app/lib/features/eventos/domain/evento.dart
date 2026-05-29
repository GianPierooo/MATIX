import 'package:flutter/foundation.dart';

import 'recurrencia.dart';

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
    this.recordatorioOffsetMin,
    this.regla,
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
  /// Recordatorio como offset en minutos antes del inicio (NULL = sin
  /// recordatorio, 0 = a la hora). Fuente de verdad del preset que se
  /// muestra en el detalle; `recordarEn` es su espejo absoluto.
  final int? recordatorioOffsetMin;
  /// Regla de recurrencia de la serie (Calendario · Paso 3), o `null` si el
  /// evento es único. `iniciaEn` es el ancla (primera ocurrencia).
  final ReglaRecurrencia? regla;
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

  bool get esRecurrente => regla != null;

  /// Copia el evento desplazado a la fecha/hora de una ocurrencia concreta,
  /// conservando la duración. Pensado para mostrar ocurrencias expandidas en
  /// el calendario sin tocar la serie; mantiene el mismo `id` (sigue
  /// apuntando a la fila ancla) y limpia la regla porque ya es una instancia.
  Evento copyConInicio(DateTime nuevoInicio) {
    final fin = terminaEn != null
        ? nuevoInicio.add(terminaEn!.difference(iniciaEn))
        : null;
    return Evento(
      id: id,
      titulo: titulo,
      descripcion: descripcion,
      iniciaEn: nuevoInicio,
      terminaEn: fin,
      todoElDia: todoElDia,
      ubicacion: ubicacion,
      cursoId: cursoId,
      proyectoId: proyectoId,
      color: color,
      recordarEn: recordarEn,
      recordatorioOffsetMin: recordatorioOffsetMin,
      regla: null,
      origen: origen,
      externalId: externalId,
      googleUpdatedAt: googleUpdatedAt,
      creadoEn: creadoEn,
      actualizadoEn: actualizadoEn,
    );
  }

  /// `true` si una ocurrencia del evento empieza en el día local `dia`.
  /// Para eventos únicos compara el día del inicio; para recurrentes expande
  /// la regla restringida a ese día.
  bool ocurreEn(DateTime dia) {
    if (regla != null) {
      return eventoOcurreEnDia(
        regla: regla!,
        inicioSerie: iniciaEn.toLocal(),
        dia: dia,
      );
    }
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
        recordatorioOffsetMin: (json['recordatorio_offset_min'] as num?)?.toInt(),
        regla: ReglaRecurrencia.maybeFromEventoJson(json),
        origen: (json['origen'] as String?) ?? 'manual',
        externalId: json['external_id'] as String?,
        googleUpdatedAt: json['google_updated_at'] == null
            ? null
            : DateTime.parse(json['google_updated_at'] as String),
        creadoEn: DateTime.parse(json['creado_en'] as String),
        actualizadoEn: DateTime.parse(json['actualizado_en'] as String),
      );
}
