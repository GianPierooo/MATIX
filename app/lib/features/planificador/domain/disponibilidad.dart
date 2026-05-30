import 'planificador.dart' show VentanaTrabajo;

/// Disponibilidad de aprendizaje/trabajo (Fase 3).
///
/// Modela CUÁNDO estás libre, por día de la semana — no una sola ventana
/// global. Es la foto que el planificador de sesiones (Fase 4) usará
/// para encajar tu tiempo real: solo los huecos dentro de tu
/// disponibilidad que no choquen con eventos ni caigan en las horas de
/// silencio. Acá solo está el MODELO + el cálculo de huecos; el
/// planificador que arma sesiones es aparte (Fase 4).

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
