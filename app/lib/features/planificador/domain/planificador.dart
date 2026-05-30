import '../../eventos/domain/evento.dart';
import '../../nudges/domain/nudges.dart' show HorasSilencio;
import '../../tareas/domain/tarea.dart';
import 'disponibilidad.dart';

/// Planificador del día (Capa 7 · Urgencia-3).
///
/// Le pides a Matix "planifica mi día" y te propone bloques de tiempo
/// para tus tareas pendientes encajándolas en los huecos REALES: dentro
/// de tu ventana de trabajo, sin encimar eventos, fuera de las horas de
/// silencio, y respetando los plazos. Si no entra todo, lo dice.
///
/// Acá vive la lógica PURA (sin red ni reloj implícito): el cálculo de
/// huecos y el encaje. La estimación de duración la aporta Matix (LLM);
/// el encaje es determinístico para que las garantías (no encimar,
/// ventana, silencio) sean firmes y testeables.

/// Ventana de trabajo: horas locales entre las que se planifica.
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

class Intervalo {
  const Intervalo(this.inicio, this.fin);
  final DateTime inicio;
  final DateTime fin;
  Duration get duracion => fin.difference(inicio);
}

/// Un bloque propuesto para una tarea. `inicio`/`fin` son mutables para
/// que la revisión permita ajustarlos antes de aceptar.
class BloquePropuesto {
  BloquePropuesto({
    required this.tareaId,
    required this.titulo,
    required this.inicio,
    required this.fin,
  });
  final String tareaId;
  final String titulo;
  DateTime inicio;
  DateTime fin;

  Duration get duracion => fin.difference(inicio);
}

/// Una tarea que no entró hoy, con el motivo honesto.
class TareaSinEspacio {
  const TareaSinEspacio(this.tareaId, this.titulo, this.motivo);
  final String tareaId;
  final String titulo;
  final String motivo;
}

/// Resultado del plan: los bloques que entran, lo que se queda fuera, y
/// una nota honesta para mostrar.
class ResultadoPlan {
  const ResultadoPlan({
    required this.bloques,
    required this.sinEspacio,
    required this.nota,
  });
  final List<BloquePropuesto> bloques;
  final List<TareaSinEspacio> sinEspacio;
  final String nota;

  bool get vacio => bloques.isEmpty && sinEspacio.isEmpty;
}

bool _noDespuesDe(DateTime a, DateTime b) => !a.isAfter(b); // a <= b

/// Tramos de las horas de silencio que caen en el día de [hoy].
List<Intervalo> _tramosSilencio(DateTime hoy, HorasSilencio s) {
  final d = DateTime(hoy.year, hoy.month, hoy.day);
  final finDia = d.add(const Duration(days: 1));
  if (s.inicio == s.fin) return const [];
  if (s.inicio < s.fin) {
    // Ventana en el mismo día.
    return [Intervalo(DateTime(d.year, d.month, d.day, s.inicio),
        DateTime(d.year, d.month, d.day, s.fin))];
  }
  // Cruza medianoche: madrugada [00:00, fin) y noche [inicio, 24:00).
  return [
    Intervalo(d, DateTime(d.year, d.month, d.day, s.fin)),
    Intervalo(DateTime(d.year, d.month, d.day, s.inicio), finDia),
  ];
}

/// Resta el intervalo [o] de [l]; devuelve 0, 1 o 2 trozos.
List<Intervalo> _restar(Intervalo l, Intervalo o) {
  // Sin solape.
  if (_noDespuesDe(o.fin, l.inicio) || _noDespuesDe(l.fin, o.inicio)) {
    return [l];
  }
  final res = <Intervalo>[];
  if (o.inicio.isAfter(l.inicio)) res.add(Intervalo(l.inicio, o.inicio));
  if (o.fin.isBefore(l.fin)) res.add(Intervalo(o.fin, l.fin));
  return res;
}

bool _mismoDia(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Huecos disponibles de un [dia] (Fase 3): la ventana de disponibilidad
/// de ese día menos los eventos que lo ocupan y las horas de silencio.
/// Si [ventana] es null, ese día no hay disponibilidad → sin huecos.
/// Si se pasa [ahora] y [dia] es hoy, no devuelve huecos en el pasado.
/// Ordenados por inicio. Es la base que consumirá Fase 4.
List<Intervalo> huecosDisponibles({
  required DateTime dia,
  required VentanaTrabajo? ventana,
  required HorasSilencio silencio,
  required List<Evento> eventos,
  DateTime? ahora,
}) {
  if (ventana == null) return const [];
  final d = DateTime(dia.year, dia.month, dia.day);
  var inicioDia = DateTime(d.year, d.month, d.day, ventana.inicio);
  final finDia = DateTime(d.year, d.month, d.day, ventana.fin);
  // Si `dia` es hoy y la ventana ya arrancó, no planificar el pasado.
  if (ahora != null && _mismoDia(ahora, d) && inicioDia.isBefore(ahora)) {
    inicioDia = ahora;
  }
  if (!inicioDia.isBefore(finDia)) return const [];

  final ocupado = <Intervalo>[];
  for (final e in eventos) {
    if (e.todoElDia) {
      ocupado.add(Intervalo(inicioDia, finDia));
      continue;
    }
    final ini = e.iniciaEn.toLocal();
    final fin =
        (e.terminaEn ?? e.iniciaEn.add(const Duration(hours: 1))).toLocal();
    ocupado.add(Intervalo(ini, fin));
  }
  ocupado.addAll(_tramosSilencio(d, silencio));

  var libres = <Intervalo>[Intervalo(inicioDia, finDia)];
  for (final o in ocupado) {
    libres = libres.expand((l) => _restar(l, o)).toList();
  }
  libres = libres.where((l) => l.duracion > Duration.zero).toList()
    ..sort((a, b) => a.inicio.compareTo(b.inicio));
  return libres;
}

int _rankPrioridad(Prioridad p) => switch (p) {
      Prioridad.alta => 0,
      Prioridad.media => 1,
      Prioridad.baja => 2,
    };

/// Arma el plan del día: encaja [tareas] en los huecos libres usando
/// [duracionesMin] (minutos por tarea; default [duracionDefaultMin] si
/// no hay estimación). Ordena por plazo (más cercano primero) y luego
/// por prioridad. Reporta honestamente lo que no entra.
ResultadoPlan planificarDia({
  required List<Tarea> tareas,
  required List<Evento> eventos,
  required DateTime ahora,
  required DisponibilidadSemanal disponibilidad,
  required HorasSilencio silencio,
  required Map<String, int> duracionesMin,
  int duracionDefaultMin = 45,
}) {
  final orden = [...tareas]..sort((a, b) {
      final ad = a.plazoEfectivo;
      final bd = b.plazoEfectivo;
      if (ad != null && bd != null) {
        final c = ad.compareTo(bd);
        if (c != 0) return c;
      } else if (ad != null) {
        return -1;
      } else if (bd != null) {
        return 1;
      }
      return _rankPrioridad(a.prioridad).compareTo(_rankPrioridad(b.prioridad));
    });

  final disp = [
    ...huecosDisponibles(
      dia: ahora,
      ventana: disponibilidad.ventanaDe(ahora),
      silencio: silencio,
      eventos: eventos,
      ahora: ahora,
    )
  ];
  final bloques = <BloquePropuesto>[];
  final sinEspacio = <TareaSinEspacio>[];

  for (final t in orden) {
    final dur = Duration(minutes: duracionesMin[t.id] ?? duracionDefaultMin);
    final tope = t.venceEn?.toLocal(); // debe terminar antes del plazo real
    var idx = -1;
    for (var i = 0; i < disp.length; i++) {
      if (disp[i].duracion < dur) continue;
      final fin = disp[i].inicio.add(dur);
      if (tope != null && fin.isAfter(tope)) continue;
      idx = i;
      break;
    }
    if (idx == -1) {
      sinEspacio.add(TareaSinEspacio(
        t.id,
        t.titulo,
        tope != null
            ? 'No alcanza el tiempo antes de su plazo'
            : 'No hay hueco libre hoy',
      ));
      continue;
    }
    final iv = disp[idx];
    final fin = iv.inicio.add(dur);
    bloques.add(BloquePropuesto(
      tareaId: t.id,
      titulo: t.titulo,
      inicio: iv.inicio,
      fin: fin,
    ));
    if (fin.isBefore(iv.fin)) {
      disp[idx] = Intervalo(fin, iv.fin);
    } else {
      disp.removeAt(idx);
    }
  }

  bloques.sort((a, b) => a.inicio.compareTo(b.inicio));
  final nota = sinEspacio.isEmpty
      ? (bloques.isEmpty
          ? 'No hay tareas pendientes para planificar.'
          : 'Te entra todo hoy: ${bloques.length} '
              '${bloques.length == 1 ? "bloque" : "bloques"}.')
      : 'No te entra todo hoy. ${sinEspacio.length} '
          '${sinEspacio.length == 1 ? "tarea queda" : "tareas quedan"} '
          'para otro día.';
  return ResultadoPlan(bloques: bloques, sinEspacio: sinEspacio, nota: nota);
}
