import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notificaciones_service.dart';
import '../../../core/providers.dart';
import '../data/cierre_prefs.dart';
import '../data/cierre_repository.dart';

final cierreRepositoryProvider = Provider<CierreRepository>((ref) {
  return CierreRepository(ref.watch(matixClientProvider));
});

/// Cierre de hoy — se refresca al entrar a la pantalla.
final cierreHoyProvider = FutureProvider<CierreHoy>((ref) async {
  return ref.watch(cierreRepositoryProvider).hoy();
});

final cierrePrefsProvider = Provider<CierrePrefs>((_) => CierrePrefs());

/// Estado del switch + hora del cierre del día. Espejo del
/// `BriefingConfigController` pero con su id, payload y defaults.
class CierreConfigController extends StateNotifier<CierreConfig> {
  CierreConfigController(this._prefs, this._notis)
      : super(const CierreConfig(
          activo: false,
          hora: CierrePrefs.horaDefault,
          minuto: CierrePrefs.minutoDefault,
        )) {
    _ready = _cargar();
  }

  final CierrePrefs _prefs;
  final NotificacionesService _notis;
  late final Future<void> _ready;

  Future<void> get ready => _ready;

  Future<void> _cargar() async {
    state = await _prefs.leer();
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
      await _notis.cancelar(CierrePrefs.idNotificacion);
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
      id: CierrePrefs.idNotificacion,
      titulo: '🌙 Cierre del día',
      cuerpo: 'Abrí Matix para repasar tu día.',
      hora: hora,
      minuto: minuto,
      // El handler de `MatixApp.initState` lee este payload para
      // empujar la `CierreScreen`.
      payload: 'cierre',
    );
  }
}

final cierreConfigProvider =
    StateNotifierProvider<CierreConfigController, CierreConfig>((ref) {
  return CierreConfigController(
    ref.watch(cierrePrefsProvider),
    ref.watch(notificacionesServiceProvider),
  );
});
