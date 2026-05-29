import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notificaciones_service.dart';
import '../../../core/providers.dart';
import '../data/briefing_prefs.dart';
import '../data/briefing_repository.dart';

final briefingRepositoryProvider = Provider<BriefingRepository>((ref) {
  return BriefingRepository(ref.watch(matixClientProvider));
});

/// Briefing de hoy — lo refrescamos al entrar a la pantalla. Se
/// invalida al tocar el botón "Reintentar" en caso de error.
final briefingHoyProvider = FutureProvider<BriefingHoy>((ref) async {
  return ref.watch(briefingRepositoryProvider).hoy();
});

final briefingPrefsProvider = Provider<BriefingPrefs>((_) => BriefingPrefs());

/// Estado del switch + hora del briefing matutino. Lee de
/// SharedPreferences al arrancar y persiste cada cambio.
class BriefingConfigController extends StateNotifier<BriefingConfig> {
  BriefingConfigController(this._prefs, this._notis)
      : super(const BriefingConfig(
          activo: false,
          hora: BriefingPrefs.horaDefault,
          minuto: BriefingPrefs.minutoDefault,
        )) {
    _ready = _cargar();
  }

  final BriefingPrefs _prefs;
  final NotificacionesService _notis;
  late final Future<void> _ready;

  /// Future que completa cuando el primer load + reprogramación de
  /// arranque terminó. Los métodos públicos lo esperan para que no
  /// se entrelace con escrituras concurrentes.
  Future<void> get ready => _ready;

  Future<void> _cargar() async {
    state = await _prefs.leer();
    // Si quedó activo de una sesión anterior, reprogramamos (idempotente)
    // por si el SO reseteó las pendientes o instalamos una versión nueva.
    if (state.activo) {
      await _programar(state.hora, state.minuto);
    }
  }

  Future<void> activar(bool v) async {
    await _ready;
    if (v) {
      await _notis.pedirPermisos();
      await _programar(state.hora, state.minuto);
    } else {
      await _notis.cancelar(BriefingPrefs.idNotificacion);
    }
    state = state.copyWith(activo: v);
    await _prefs.guardar(state);
  }

  Future<void> cambiarHora(int hora, int minuto) async {
    await _ready;
    state = state.copyWith(hora: hora, minuto: minuto);
    await _prefs.guardar(state);
    if (state.activo) {
      await _programar(hora, minuto);
    }
  }

  Future<void> _programar(int hora, int minuto) async {
    await _notis.programarDiaria(
      id: BriefingPrefs.idNotificacion,
      titulo: '🌅 Briefing de hoy',
      cuerpo: 'Abrí Matix para ver tu resumen del día.',
      hora: hora,
      minuto: minuto,
      // El payload lo lee el handler registrado en `MatixApp.initState`
      // para empujar la `BriefingScreen` al tocar la notificación.
      payload: 'briefing',
    );
  }
}

final briefingConfigProvider =
    StateNotifierProvider<BriefingConfigController, BriefingConfig>((ref) {
  return BriefingConfigController(
    ref.watch(briefingPrefsProvider),
    ref.watch(notificacionesServiceProvider),
  );
});
