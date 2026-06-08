/// Modelo de los "pendientes de confirmar": tareas pasadas no resueltas y
/// eventos fuera de casa terminados sin asistencia.
///
/// Es el respaldo IN-APP del flujo de notificaciones: si MagicOS mata las
/// notis (o el botón no llega), el seguimiento sigue vivo en la UI.
class TareaPendiente {
  const TareaPendiente({
    required this.id,
    required this.titulo,
    required this.vencioHaceMin,
    this.proyectoId,
  });

  final String id;
  final String titulo;
  final int vencioHaceMin;
  final String? proyectoId;

  factory TareaPendiente.fromJson(Map<String, dynamic> j) => TareaPendiente(
        id: j['id'] as String,
        titulo: (j['titulo'] as String?) ?? 'Tarea',
        vencioHaceMin: (j['vencio_hace_min'] as num?)?.toInt() ?? 0,
        proyectoId: j['proyecto_id'] as String?,
      );
}

class EventoPendiente {
  const EventoPendiente({
    required this.id,
    required this.titulo,
    required this.terminoHaceMin,
    this.ubicacion,
  });

  final String id;
  final String titulo;
  final int terminoHaceMin;
  final String? ubicacion;

  factory EventoPendiente.fromJson(Map<String, dynamic> j) => EventoPendiente(
        id: j['id'] as String,
        titulo: (j['titulo'] as String?) ?? 'Evento',
        terminoHaceMin: (j['termino_hace_min'] as num?)?.toInt() ?? 0,
        ubicacion: j['ubicacion'] as String?,
      );
}

class PendientesConfirmacion {
  const PendientesConfirmacion({
    required this.tareas,
    required this.eventos,
  });

  final List<TareaPendiente> tareas;
  final List<EventoPendiente> eventos;

  bool get vacio => tareas.isEmpty && eventos.isEmpty;
  int get total => tareas.length + eventos.length;

  factory PendientesConfirmacion.fromJson(Map<String, dynamic> j) =>
      PendientesConfirmacion(
        tareas: ((j['tareas'] as List<dynamic>?) ?? const [])
            .map((e) => TareaPendiente.fromJson(e as Map<String, dynamic>))
            .toList(),
        eventos: ((j['eventos'] as List<dynamic>?) ?? const [])
            .map((e) => EventoPendiente.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static const vacia = PendientesConfirmacion(tareas: [], eventos: []);
}

/// Texto humano del "hace cuánto" (ej. "hace 35 min", "hace 2 h 15 min"). PURO.
String humanoDesde(int min) {
  if (min < 1) return 'hace un momento';
  if (min < 60) return 'hace $min min';
  final h = min ~/ 60;
  final m = min % 60;
  if (m == 0) return 'hace $h h';
  return 'hace $h h $m min';
}
