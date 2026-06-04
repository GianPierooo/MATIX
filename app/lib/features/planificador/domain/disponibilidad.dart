// Disponibilidad de aprendizaje/trabajo.
//
// Modela CUÁNDO estás libre, por día de la semana. La consume el ajuste de
// «Disponibilidad por día» en Ajustes, que la sincroniza al cerebro (config
// de nudges): el scheduler solo te empuja dentro de tus ventanas. La
// colocación del plan en el tiempo la hace la capa de horario del cerebro
// (vista «Hoy»), no este modelo.

/// Ventana de trabajo: horas locales entre las que estás disponible.
class VentanaTrabajo {
  const VentanaTrabajo({this.inicio = 9, this.fin = 21});
  final int inicio;
  final int fin;

  @override
  bool operator ==(Object other) =>
      other is VentanaTrabajo && other.inicio == inicio && other.fin == fin;
  @override
  int get hashCode => Object.hash(inicio, fin);
}

/// Disponibilidad de un día: si está activo y entre qué horas (locales).
class DisponibilidadDia {
  const DisponibilidadDia({this.activo = true, this.inicio = 9, this.fin = 21});

  final bool activo;
  final int inicio;
  final int fin;

  /// La ventana del día, o null si ese día no hay disponibilidad
  /// (apagado o rango inválido).
  VentanaTrabajo? get ventana =>
      (activo && fin > inicio) ? VentanaTrabajo(inicio: inicio, fin: fin) : null;

  DisponibilidadDia copyWith({bool? activo, int? inicio, int? fin}) =>
      DisponibilidadDia(
        activo: activo ?? this.activo,
        inicio: inicio ?? this.inicio,
        fin: fin ?? this.fin,
      );

  @override
  bool operator ==(Object other) =>
      other is DisponibilidadDia &&
      other.activo == activo &&
      other.inicio == inicio &&
      other.fin == fin;
  @override
  int get hashCode => Object.hash(activo, inicio, fin);
}

/// Disponibilidad por día de la semana (ISO: 1=lunes … 7=domingo).
class DisponibilidadSemanal {
  const DisponibilidadSemanal(this.porDia);

  /// Mapa día ISO (1..7) → disponibilidad. Un día ausente cuenta como
  /// no disponible.
  final Map<int, DisponibilidadDia> porDia;

  DisponibilidadDia diaDe(int weekday) =>
      porDia[weekday] ?? const DisponibilidadDia(activo: false);

  /// La ventana del día calendario [d] (según su día de semana), o null
  /// si ese día no hay disponibilidad.
  VentanaTrabajo? ventanaDe(DateTime d) => diaDe(d.weekday).ventana;

  /// Copia con un día cambiado.
  DisponibilidadSemanal conDia(int weekday, DisponibilidadDia dia) =>
      DisponibilidadSemanal({...porDia, weekday: dia});

  /// Misma ventana todos los días (útil de default y en tests).
  factory DisponibilidadSemanal.uniforme({int inicio = 9, int fin = 21}) =>
      DisponibilidadSemanal({
        for (var d = 1; d <= 7; d++)
          d: DisponibilidadDia(activo: true, inicio: inicio, fin: fin),
      });

  /// Default: todos los días 09:00–21:00. El usuario lo afina por día.
  static DisponibilidadSemanal get porDefecto =>
      DisponibilidadSemanal.uniforme();
}

/// Nombres cortos de los días ISO 1..7 (lunes→domingo), para la UI.
const List<String> nombresDiaCorto = [
  'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom',
];
