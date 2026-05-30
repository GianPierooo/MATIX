import '../../eventos/domain/recurrencia.dart';

/// Tipo de evento propuesto desde un sílabo/horario (Cámara · sílabo):
/// una clase RECURRENTE (semanal) o una fecha ÚNICA (parcial, entrega).
enum TipoEventoPropuesto {
  recurrente,
  unico;

  static TipoEventoPropuesto fromJson(String? s) =>
      s == 'recurrente' ? TipoEventoPropuesto.recurrente : TipoEventoPropuesto.unico;

  String get label => switch (this) {
        TipoEventoPropuesto.recurrente => 'Recurrente',
        TipoEventoPropuesto.unico => 'Única',
      };
}

/// Un evento candidato extraído del sílabo. Inmutable; las ediciones de
/// la hoja de revisión generan copias con `copyWith` (como las tareas).
class EventoPropuesto {
  const EventoPropuesto({
    required this.tipo,
    required this.titulo,
    this.diasSemana = const {},
    this.horaInicio,
    this.horaFin,
    this.fecha,
    this.cursoId,
    this.color,
  });

  final TipoEventoPropuesto tipo;
  final String titulo;

  /// Días ISO (1=lunes … 7=domingo). Solo para [TipoEventoPropuesto.recurrente].
  final Set<int> diasSemana;

  /// "HH:MM" o null.
  final String? horaInicio;
  final String? horaFin;

  /// Fecha del evento único.
  final DateTime? fecha;

  /// Curso asignado (y su color) — opcional, se elige en la revisión.
  final String? cursoId;
  final String? color;

  bool get esRecurrente => tipo == TipoEventoPropuesto.recurrente;

  factory EventoPropuesto.fromCerebro(Map<String, dynamic> j) {
    final dias = ((j['dias_semana'] as List?) ?? const [])
        .whereType<num>()
        .map((e) => e.toInt())
        .where((d) => d >= 1 && d <= 7)
        .toSet();
    final fechaRaw = j['fecha'];
    return EventoPropuesto(
      tipo: TipoEventoPropuesto.fromJson(j['tipo'] as String?),
      titulo: (j['titulo'] as String?)?.trim() ?? '',
      diasSemana: dias,
      horaInicio: j['hora_inicio'] as String?,
      horaFin: j['hora_fin'] as String?,
      fecha: fechaRaw is String ? DateTime.tryParse(fechaRaw) : null,
    );
  }

  EventoPropuesto copyWith({
    String? titulo,
    Set<int>? diasSemana,
    Object? horaInicio = _sentinel,
    Object? horaFin = _sentinel,
    Object? fecha = _sentinel,
    Object? cursoId = _sentinel,
    Object? color = _sentinel,
  }) {
    return EventoPropuesto(
      tipo: tipo,
      titulo: titulo ?? this.titulo,
      diasSemana: diasSemana ?? this.diasSemana,
      horaInicio:
          identical(horaInicio, _sentinel) ? this.horaInicio : horaInicio as String?,
      horaFin: identical(horaFin, _sentinel) ? this.horaFin : horaFin as String?,
      fecha: identical(fecha, _sentinel) ? this.fecha : fecha as DateTime?,
      cursoId: identical(cursoId, _sentinel) ? this.cursoId : cursoId as String?,
      color: identical(color, _sentinel) ? this.color : color as String?,
    );
  }

  static const _sentinel = Object();
}

/// `(hora, minuto)` de un "HH:MM", o null si no parsea.
(int, int)? parseHora(String? s) {
  if (s == null) return null;
  final p = s.split(':');
  if (p.length != 2) return null;
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
  return (h, m);
}

/// La próxima fecha (de hoy en adelante, ventana de 7 días) cuyo día ISO
/// está en [diasSemana]; sirve de ancla para una serie recurrente. Null
/// si [diasSemana] está vacío.
DateTime? proximaFechaConDia(Set<int> diasSemana, DateTime ahora) {
  if (diasSemana.isEmpty) return null;
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  for (var i = 0; i < 7; i++) {
    final d = hoy.add(Duration(days: i));
    if (diasSemana.contains(d.weekday)) return d;
  }
  return hoy;
}

/// Parámetros listos para `EventosRepository.crear`, derivados de un
/// [EventoPropuesto]. Lógica pura (testeable): convierte tipo + días +
/// horas + fecha en `iniciaEn` / `terminaEn` / `todoElDia` / `regla`.
class ParametrosEvento {
  const ParametrosEvento({
    required this.iniciaEn,
    this.terminaEn,
    this.todoElDia = false,
    this.regla,
  });
  final DateTime iniciaEn;
  final DateTime? terminaEn;
  final bool todoElDia;
  final ReglaRecurrencia? regla;
}

ParametrosEvento parametrosDe(EventoPropuesto p, DateTime ahora) {
  if (p.esRecurrente) {
    final base = proximaFechaConDia(p.diasSemana, ahora) ??
        DateTime(ahora.year, ahora.month, ahora.day);
    final hi = parseHora(p.horaInicio) ?? (8, 0);
    final inicia = DateTime(base.year, base.month, base.day, hi.$1, hi.$2);
    final hf = parseHora(p.horaFin);
    final termina = hf == null
        ? null
        : DateTime(base.year, base.month, base.day, hf.$1, hf.$2);
    return ParametrosEvento(
      iniciaEn: inicia,
      terminaEn: termina,
      regla: ReglaRecurrencia(
        frecuencia: FrecuenciaRecurrencia.semanal,
        diasSemana: p.diasSemana,
        fin: FinRecurrencia.nunca,
      ),
    );
  }
  // Único.
  final f = p.fecha ?? DateTime(ahora.year, ahora.month, ahora.day);
  final hi = parseHora(p.horaInicio);
  if (hi == null) {
    // Sin hora → todo el día.
    return ParametrosEvento(
      iniciaEn: DateTime(f.year, f.month, f.day),
      todoElDia: true,
    );
  }
  final inicia = DateTime(f.year, f.month, f.day, hi.$1, hi.$2);
  final hf = parseHora(p.horaFin);
  final termina =
      hf == null ? null : DateTime(f.year, f.month, f.day, hf.$1, hf.$2);
  return ParametrosEvento(iniciaEn: inicia, terminaEn: termina);
}
