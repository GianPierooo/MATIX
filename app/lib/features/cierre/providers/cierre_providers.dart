import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../rituales/data/rituales_repository.dart';
import '../data/cierre_prefs.dart';
import '../data/cierre_repository.dart';

final cierreRepositoryProvider = Provider<CierreRepository>((ref) {
  return CierreRepository(ref.watch(matixClientProvider));
});

/// Cierre de hoy — se refresca al entrar a la pantalla.
final cierreHoyProvider = FutureProvider<CierreHoy>((ref) async {
  return ref.watch(cierreRepositoryProvider).hoy();
});

/// Estado del switch + hora del cierre del día. Espejo del
/// `BriefingConfigController`: la config vive en el cerebro (Push Capa 3a)
/// y el scheduler dispara el push. Default ON, 22:00.
class CierreConfigController extends StateNotifier<CierreConfig> {
  CierreConfigController(this._repo)
      : super(const CierreConfig(activo: true, hora: 22, minuto: 0)) {
    _ready = _cargar();
  }

  final RitualesRepository _repo;
  late final Future<void> _ready;

  /// Completa cuando terminó el primer load desde el cerebro.
  Future<void> get ready => _ready;

  Future<void> _cargar() async {
    try {
      final c = await _repo.obtener('cierre');
      if (c != null) {
        state = CierreConfig(activo: c.activo, hora: c.hora, minuto: c.minuto);
      }
    } catch (_) {
      // Sin red / migración sin aplicar: dejamos el default (ON, 22:00).
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
        'cierre',
        activo: state.activo,
        hora: state.hora,
        minuto: state.minuto,
      );
    } catch (_) {
      // Best-effort.
    }
  }
}

final cierreConfigProvider =
    StateNotifierProvider<CierreConfigController, CierreConfig>((ref) {
  return CierreConfigController(ref.watch(ritualesRepositoryProvider));
});
