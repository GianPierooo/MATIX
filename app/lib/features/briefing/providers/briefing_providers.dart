import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../rituales/data/rituales_repository.dart';
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

/// Estado del switch + hora del briefing matutino. La fuente de verdad es
/// el CEREBRO (Push Capa 3a): lee la config del servidor al arrancar y
/// persiste cada cambio ahí. El push lo dispara el scheduler del cerebro,
/// no una alarma local. Default ON (lo trae el servidor, sembrado activo).
class BriefingConfigController extends StateNotifier<BriefingConfig> {
  BriefingConfigController(this._repo)
      : super(const BriefingConfig(activo: true, hora: 8, minuto: 0)) {
    _ready = _cargar();
  }

  final RitualesRepository _repo;
  late final Future<void> _ready;

  /// Completa cuando terminó el primer load desde el cerebro.
  Future<void> get ready => _ready;

  Future<void> _cargar() async {
    try {
      final c = await _repo.obtener('briefing');
      if (c != null) {
        state = BriefingConfig(
          activo: c.activo,
          hora: c.hora,
          minuto: c.minuto,
        );
      }
    } catch (_) {
      // Sin red / migración sin aplicar: dejamos el default (ON, 08:00).
    }
  }

  Future<void> activar(bool v) async {
    state = state.copyWith(activo: v);
    await _guardar();
  }

  Future<void> cambiarHora(int hora, int minuto) async {
    state = state.copyWith(hora: hora, minuto: minuto);
    await _guardar();
  }

  Future<void> _guardar() async {
    try {
      await _repo.actualizar(
        'briefing',
        activo: state.activo,
        hora: state.hora,
        minuto: state.minuto,
      );
    } catch (_) {
      // Best-effort: el estado local ya cambió; reintenta en el próximo
      // toque. (Sin red no podemos persistir.)
    }
  }
}

final briefingConfigProvider =
    StateNotifierProvider<BriefingConfigController, BriefingConfig>((ref) {
  return BriefingConfigController(ref.watch(ritualesRepositoryProvider));
});
