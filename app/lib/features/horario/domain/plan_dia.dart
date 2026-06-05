import 'package:flutter/foundation.dart';

/// Un bloque del plan del día: fijo (clase/evento/ancla, inmovible) o
/// planificado (trabajo/skill/tarea, tentativo y ajustable).
@immutable
class BloquePlan {
  const BloquePlan({
    required this.inicio,
    required this.fin,
    required this.titulo,
    required this.tipo,
    required this.tentativo,
    this.proyecto,
    this.skill,
    this.nodoId,
    this.tareaId,
    this.setItemId,
  });

  final String inicio; // "HH:MM" (hora Lima)
  final String fin; // "HH:MM"
  final String titulo;
  final String tipo; // clase | evento | ancla | trabajo | skill | tarea
  final bool tentativo; // true = ajustable; false = fijo/inmovible
  final String? proyecto;
  final String? skill;
  final String? nodoId;
  final String? tareaId;
  final String? setItemId;

  bool get esFijo => !tentativo;
  int get inicioMin => minDesdeHHMM(inicio);
  int get finMin => minDesdeHHMM(fin);

  /// Clave estable para identificar el bloque entre recargas (ediciones de hora,
  /// ocultar al saltar). Usa los ids reales si existen.
  String get clave =>
      tareaId ?? nodoId ?? setItemId ?? '$tipo|$titulo|$inicio';

  /// Copia con horas nuevas (edición ligera de hora en la vista).
  BloquePlan conHoras(String nuevoInicio, String nuevoFin) => BloquePlan(
        inicio: nuevoInicio,
        fin: nuevoFin,
        titulo: titulo,
        tipo: tipo,
        tentativo: tentativo,
        proyecto: proyecto,
        skill: skill,
        nodoId: nodoId,
        tareaId: tareaId,
        setItemId: setItemId,
      );

  factory BloquePlan.fromJson(Map<String, dynamic> j) => BloquePlan(
        inicio: (j['inicio'] as String?) ?? '00:00',
        fin: (j['fin'] as String?) ?? '00:00',
        titulo: (j['titulo'] as String?) ?? '',
        tipo: (j['tipo'] as String?) ?? 'trabajo',
        tentativo: j['tentativo'] as bool? ?? false,
        proyecto: j['proyecto'] as String?,
        skill: j['skill'] as String?,
        nodoId: j['nodo_id'] as String?,
        tareaId: j['tarea_id'] as String?,
        setItemId: j['set_item_id'] as String?,
      );
}

/// Algo que NO entró hoy (capacidad honesta: se recortó por prioridad).
@immutable
class FueraPlan {
  const FueraPlan({required this.titulo, required this.tipo, required this.motivo});
  final String titulo;
  final String tipo;
  final String motivo;

  factory FueraPlan.fromJson(Map<String, dynamic> j) => FueraPlan(
        titulo: (j['titulo'] as String?) ?? '',
        tipo: (j['tipo'] as String?) ?? '',
        motivo: (j['motivo'] as String?) ?? '',
      );
}

/// Una sugerencia ofrecible en un hueco libre: práctica de skill o tarea de
/// proyecto corto que no entró al plan. Se ofrece, no se impone: la app dosifica
/// (una por hueco, casada por tamaño) y el usuario decide tocarla o dejarla.
@immutable
class Sugerencia {
  const Sugerencia({
    required this.titulo,
    required this.tipo,
    required this.durMin,
    this.proyecto,
    this.skill,
    this.nodoId,
    this.tareaId,
    this.setItemId,
  });

  final String titulo;
  final String tipo; // trabajo | skill | tarea
  final int durMin; // duración estimada (para casar con el hueco)
  final String? proyecto;
  final String? skill;
  final String? nodoId;
  final String? tareaId;
  final String? setItemId;

  /// Clave estable para no repetir la misma sugerencia entre huecos.
  String get clave => tareaId ?? nodoId ?? setItemId ?? '$tipo|$titulo';

  factory Sugerencia.fromJson(Map<String, dynamic> j) => Sugerencia(
        titulo: (j['titulo'] as String?) ?? '',
        tipo: (j['tipo'] as String?) ?? 'tarea',
        durMin: (j['dur_min'] as num?)?.toInt() ?? 30,
        proyecto: j['proyecto'] as String?,
        skill: j['skill'] as String?,
        nodoId: j['nodo_id'] as String?,
        tareaId: j['tarea_id'] as String?,
        setItemId: j['set_item_id'] as String?,
      );

  /// Convierte la sugerencia aceptada en un bloque tentativo del plan, colocado
  /// al inicio del hueco con su duración (acotada al hueco disponible).
  BloquePlan aBloque(int iniMin, int huecoMin) {
    final dur = durMin.clamp(15, huecoMin);
    return BloquePlan(
      inicio: hhmmDesdeMin(iniMin),
      fin: hhmmDesdeMin(iniMin + dur),
      titulo: titulo,
      tipo: tipo,
      tentativo: true,
      proyecto: proyecto,
      skill: skill,
      nodoId: nodoId,
      tareaId: tareaId,
      setItemId: setItemId,
    );
  }
}

/// El plan del día que devuelve el cerebro (capa de horario).
@immutable
class PlanDia {
  const PlanDia({
    required this.fecha,
    required this.despierta,
    required this.duerme,
    required this.bloques,
    required this.fuera,
    this.sugerencias = const [],
    this.desde,
  });

  final String fecha; // ISO date
  final String despierta; // "HH:MM"
  final String duerme; // "HH:MM"
  final String? desde; // "HH:MM" si es replan desde la hora actual
  final List<BloquePlan> bloques;
  final List<FueraPlan> fuera;
  final List<Sugerencia> sugerencias;

  bool get vacio => bloques.isEmpty;
  bool get esReplan => desde != null;
  List<BloquePlan> get tentativos => bloques.where((b) => b.tentativo).toList();

  factory PlanDia.fromJson(Map<String, dynamic> j) => PlanDia(
        fecha: (j['fecha'] as String?) ?? '',
        despierta: (j['despierta'] as String?) ?? '07:00',
        duerme: (j['duerme'] as String?) ?? '23:00',
        desde: j['desde'] as String?,
        bloques: ((j['bloques'] as List<dynamic>?) ?? const [])
            .map((e) => BloquePlan.fromJson(e as Map<String, dynamic>))
            .toList(),
        fuera: ((j['fuera'] as List<dynamic>?) ?? const [])
            .map((e) => FueraPlan.fromJson(e as Map<String, dynamic>))
            .toList(),
        sugerencias: ((j['sugerencias'] as List<dynamic>?) ?? const [])
            .map((e) => Sugerencia.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Elige UNA sugerencia para un hueco de [huecoMin] minutos, de entre el [pool],
/// saltando las ya usadas (en [usadas]). Prefiere la de mayor duración que aún
/// quepa (aprovecha el hueco sin pasarse). Devuelve `null` si ninguna cabe.
/// PURA: la usa la vista para dosificar (una por hueco) y es testeable.
Sugerencia? elegirSugerencia(
  List<Sugerencia> pool,
  int huecoMin, {
  Set<String> usadas = const {},
  int saltar = 0,
}) {
  final caben = pool
      .where((s) => !usadas.contains(s.clave) && s.durMin <= huecoMin)
      .toList()
    ..sort((a, b) => b.durMin.compareTo(a.durMin));
  if (caben.isEmpty) return null;
  return caben[saltar % caben.length];
}

// ── Helpers puros (sin Flutter UI, testeables) ───────────────────────────────

/// "HH:MM" → minutos desde medianoche (0 si no parsea).
int minDesdeHHMM(String hhmm) {
  final partes = hhmm.split(':');
  if (partes.length != 2) return 0;
  final h = int.tryParse(partes[0]) ?? 0;
  final m = int.tryParse(partes[1]) ?? 0;
  return h * 60 + m;
}

/// minutos → "HH:MM".
String hhmmDesdeMin(int min) {
  final m = min.clamp(0, 24 * 60 - 1);
  final hh = (m ~/ 60).toString().padLeft(2, '0');
  final mm = (m % 60).toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// Hueco libre (minutos) entre el fin de un bloque y el inicio del siguiente.
/// Negativo o cero si no hay hueco.
int huecoMin(String finPrev, String iniSig) =>
    minDesdeHHMM(iniSig) - minDesdeHHMM(finPrev);

/// ¿Vale la pena mostrar el hueco como "libre"? (ignora micro-huecos).
bool huecoVisible(String finPrev, String iniSig, {int minimo = 20}) =>
    huecoMin(finPrev, iniSig) >= minimo;

/// "#RRGGBB" → ARGB int (0xFFRRGGBB), o null si no parsea. Pura: no toca dart:ui.
int? argbDeHex(String? hex) {
  if (hex == null || hex.length != 7 || !hex.startsWith('#')) return null;
  final v = int.tryParse(hex.substring(1), radix: 16);
  if (v == null) return null;
  return 0xFF000000 | v;
}
