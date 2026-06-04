import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../nudges/data/nudges_repository.dart';
import '../data/planificador_prefs.dart';
import '../domain/disponibilidad.dart';

/// Preferencias locales del planificador (hoy solo guardan la
/// disponibilidad por día).
final planificadorPrefsProvider = Provider((_) => PlanificadorPrefs());

/// Estado de la disponibilidad por día: cuándo estás libre cada día. Lee de
/// prefs al arrancar y persiste cada cambio. Además sincroniza la
/// disponibilidad al CEREBRO (config de nudges): el scheduler solo te empuja
/// dentro de tus ventanas. La consume el ajuste de disponibilidad en Ajustes.
///
/// Nota: la PLANIFICACIÓN del día (colocar el set en el tiempo) ya NO vive
/// acá — es la vista «Hoy» (capa de horario del cerebro). Este controller
/// quedó solo para la disponibilidad, que sigue alimentando los nudges.
class DisponibilidadController extends StateNotifier<DisponibilidadSemanal> {
  DisponibilidadController(this._prefs, this._nudgesRepo)
      : super(DisponibilidadSemanal.porDefecto) {
    _ready = _cargar();
  }
  final PlanificadorPrefs _prefs;
  final NudgesRepository _nudgesRepo;
  late final Future<void> _ready;
  Future<void> get ready => _ready;

  Future<void> _cargar() async {
    state = await _prefs.leerDisponibilidad();
  }

  /// Cambia la disponibilidad de un día ISO (1=lun … 7=dom) y persiste.
  /// Best-effort al servidor: si la red falla, el cambio local queda igual.
  Future<void> cambiarDia(int weekday, DisponibilidadDia dia) async {
    await _ready;
    state = state.conDia(weekday, dia);
    await _prefs.guardarDisponibilidad(state);
    try {
      await _nudgesRepo.actualizar(disponibilidad: _aServidor(state));
    } catch (_) {}
  }

  /// Mapa por día ISO en string ("1".."7") → {activo, inicio, fin}, el
  /// formato que espera el cerebro.
  static Map<String, dynamic> _aServidor(DisponibilidadSemanal d) => {
        for (var w = 1; w <= 7; w++)
          '$w': {
            'activo': d.diaDe(w).activo,
            'inicio': d.diaDe(w).inicio,
            'fin': d.diaDe(w).fin,
          },
      };
}

final disponibilidadProvider =
    StateNotifierProvider<DisponibilidadController, DisponibilidadSemanal>(
        (ref) {
  return DisponibilidadController(
    ref.watch(planificadorPrefsProvider),
    ref.watch(nudgesRepositoryProvider),
  );
});
