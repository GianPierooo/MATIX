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

/// El plan del día que devuelve el cerebro (capa de horario).
@immutable
class PlanDia {
  const PlanDia({
    required this.fecha,
    required this.despierta,
    required this.duerme,
    required this.bloques,
    required this.fuera,
    this.desde,
  });

  final String fecha; // ISO date
  final String despierta; // "HH:MM"
  final String duerme; // "HH:MM"
  final String? desde; // "HH:MM" si es replan desde la hora actual
  final List<BloquePlan> bloques;
  final List<FueraPlan> fuera;

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
      );
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
