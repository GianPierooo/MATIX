import '../../../core/notif_id.dart';
import '../../tareas/domain/tarea.dart';

/// Nudges escalados (Capa 7 · Urgencia-2).
///
/// La regla de oro: la molestia ESCALA con la cercanía del plazo, no
/// fastidia parejo. Pocos y suaves cuando falta harto; más seguidos y
/// firmes a medida que se acerca. Acá vive toda la lógica pura
/// (testeable): el calendario de puntos, las horas de silencio, y el
/// plan de notificaciones por tarea.

/// Cuán agresivos son los nudges. La elige el usuario (global).
enum IntensidadNudge {
  suave,
  normal,
  fuerte;

  static IntensidadNudge fromJson(String? s) => switch (s) {
        'suave' => IntensidadNudge.suave,
        'fuerte' => IntensidadNudge.fuerte,
        _ => IntensidadNudge.normal,
      };

  String toJson() => name;

  String get label => switch (this) {
        IntensidadNudge.suave => 'Suave',
        IntensidadNudge.normal => 'Normal',
        IntensidadNudge.fuerte => 'Fuerte',
      };
}

/// Ventana diaria donde NO se manda ningún nudge (la válvula que evita
/// la máquina de ansiedad). Por horas locales; default 22:00–08:00.
/// Si [inicio] > [fin] la ventana cruza la medianoche (el caso normal).
class HorasSilencio {
  const HorasSilencio({this.inicio = 22, this.fin = 8});
  final int inicio;
  final int fin;

  @override
  bool operator ==(Object other) =>
      other is HorasSilencio && other.inicio == inicio && other.fin == fin;

  @override
  int get hashCode => Object.hash(inicio, fin);
}

/// Tope duro de nudges por tarea. Acota cuántos ids reservamos y
/// cancelamos por tarea (rango fijo 0..kMaxNudges-1), sin guardar estado.
const int kMaxNudges = 6;

/// ¿La hora local de [t] cae dentro de las horas de silencio?
bool enSilencio(DateTime t, HorasSilencio s) {
  if (s.inicio == s.fin) return false; // ventana vacía
  if (s.inicio < s.fin) {
    // Ventana en el mismo día (ej. 1–5): silencio si está en [inicio, fin).
    return t.hour >= s.inicio && t.hour < s.fin;
  }
  // Cruza medianoche (ej. 22–8): silencio si es tarde (>=inicio) o
  // madrugada (<fin).
  return t.hour >= s.inicio || t.hour < s.fin;
}

/// Si [t] cae en silencio, lo corre al siguiente momento permitido (la
/// hora [fin] del silencio). Si no, lo deja igual.
DateTime correrFueraDeSilencio(DateTime t, HorasSilencio s) {
  if (!enSilencio(t, s)) return t;
  final cruzaMedianoche = s.inicio > s.fin;
  if (cruzaMedianoche && t.hour >= s.inicio) {
    // Noche: el siguiente "fin" cae a la mañana siguiente.
    return DateTime(t.year, t.month, t.day, s.fin)
        .add(const Duration(days: 1));
  }
  // Madrugada (o ventana mismo-día): el "fin" es del mismo día.
  return DateTime(t.year, t.month, t.day, s.fin);
}

/// Offsets candidatos (antes del plazo) por intensidad. Los puntos
/// cercanos al plazo se repiten en todas las intensidades; los lejanos
/// solo en las más fuertes. Aparte va "la mañana del día" (08:00 del día
/// del plazo), que se calcula sobre la fecha del propio plazo.
List<DateTime> _candidatos(IntensidadNudge intensidad, DateTime venceEn) {
  final manana = DateTime(venceEn.year, venceEn.month, venceEn.day, 8);
  DateTime antes(Duration d) => venceEn.subtract(d);
  return switch (intensidad) {
    // Pocos y suaves: solo el día antes y unas horas antes.
    IntensidadNudge.suave => [
        antes(const Duration(days: 1)),
        antes(const Duration(hours: 3)),
      ],
    // Equilibrado: 3 días, 1 día, la mañana del día, y 3 horas antes.
    IntensidadNudge.normal => [
        antes(const Duration(days: 3)),
        antes(const Duration(days: 1)),
        manana,
        antes(const Duration(hours: 3)),
      ],
    // Encima: agrega 7 días antes y 1 hora antes.
    IntensidadNudge.fuerte => [
        antes(const Duration(days: 7)),
        antes(const Duration(days: 3)),
        antes(const Duration(days: 1)),
        manana,
        antes(const Duration(hours: 3)),
        antes(const Duration(hours: 1)),
      ],
  };
}

/// Calendario de nudges (instantes locales) para un plazo [venceEn],
/// dado [ahora]. Aplica las horas de silencio, descarta los puntos que
/// ya pasaron o que caen sobre/después del plazo, deduplica y ordena.
///
/// Los puntos se agrupan más cerca del plazo (los intervalos se
/// achican): así la presión escala con la cercanía, no parejo.
List<DateTime> calendarioNudges(
  DateTime venceEn,
  DateTime ahora, {
  IntensidadNudge intensidad = IntensidadNudge.normal,
  HorasSilencio silencio = const HorasSilencio(),
}) {
  final vistos = <int>{};
  final out = <DateTime>[];
  for (final c in _candidatos(intensidad, venceEn)) {
    final p = correrFueraDeSilencio(c, silencio);
    if (!p.isAfter(ahora)) continue; // nada en el pasado
    if (!p.isBefore(venceEn)) continue; // siempre antes del plazo
    if (vistos.add(p.millisecondsSinceEpoch)) out.add(p);
  }
  out.sort((a, b) => a.compareTo(b));
  return out;
}

/// Cuerpo del nudge: activador, referencia el tiempo restante, sin
/// reproche. Ej. "Vence en 3 horas" / "Vence en 1 día".
String cuerpoNudge(DateTime venceEn, DateTime punto) {
  return 'Vence en ${_fraseDuracion(venceEn.difference(punto))}';
}

String _fraseDuracion(Duration d) {
  if (d.inHours >= 24) {
    final n = d.inDays;
    return '$n ${n == 1 ? "día" : "días"}';
  }
  if (d.inMinutes >= 60) {
    final n = d.inHours;
    return '$n ${n == 1 ? "hora" : "horas"}';
  }
  final n = d.inMinutes;
  return '$n ${n == 1 ? "minuto" : "minutos"}';
}

/// Un nudge planificado: id estable de notificación + cuándo + cuerpo.
class PlanNudge {
  const PlanNudge({
    required this.id,
    required this.cuando,
    required this.cuerpo,
  });
  final int id;
  final DateTime cuando;
  final String cuerpo;
}

/// Plan de nudges de una tarea. Devuelve la lista vacía (no se agenda
/// nada) si la tarea está completada, no tiene plazo, o el usuario apagó
/// sus nudges. Si no, mapea el calendario a notificaciones con ids
/// estables (derivados del uuid + índice).
List<PlanNudge> planNudges(
  Tarea t,
  DateTime ahora, {
  IntensidadNudge intensidad = IntensidadNudge.normal,
  HorasSilencio silencio = const HorasSilencio(),
  bool silenciada = false,
}) {
  if (t.completada || silenciada) return const [];
  // El plazo efectivo: el bloque planificado (Urgencia-3) si lo hay, si
  // no el vencimiento real. Así los nudges escalan hacia el bloque.
  final v = t.plazoEfectivo;
  if (v == null) return const [];
  final puntos = calendarioNudges(
    v.toLocal(),
    ahora,
    intensidad: intensidad,
    silencio: silencio,
  );
  final out = <PlanNudge>[];
  for (var i = 0; i < puntos.length && i < kMaxNudges; i++) {
    out.add(PlanNudge(
      id: notifIdDeNudge(t.id, i),
      cuando: puntos[i],
      cuerpo: cuerpoNudge(v.toLocal(), puntos[i]),
    ));
  }
  return out;
}
