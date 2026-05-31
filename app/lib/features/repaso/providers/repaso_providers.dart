import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../rituales/data/rituales_repository.dart';
import '../data/repaso_repository.dart';

final repasoRepositoryProvider = Provider<RepasoRepository>(
  (ref) => RepasoRepository(ref.watch(matixClientProvider)),
);

/// Repaso de la semana. Se recalcula al entrar a la pantalla; se
/// invalida con `ref.invalidate` para reintentar.
final repasoSemanalProvider = FutureProvider<RepasoSemanal>(
  (ref) => ref.watch(repasoRepositoryProvider).obtener(),
);

// ─── Config del repaso semanal automático (4º ritual por push) ───────────

/// Estado del repaso semanal: on/off + día (ISO 1=lun … 7=dom) + hora. La
/// fuente de verdad es el CEREBRO (config_rituales): el scheduler dispara
/// el push el día y hora elegidos (Lima). Default ON, domingo 20:00.
class RepasoConfig {
  const RepasoConfig({
    this.activo = true,
    this.diaSemana = 7,
    this.hora = 20,
    this.minuto = 0,
  });

  final bool activo;
  final int diaSemana; // ISO 1=lun … 7=dom
  final int hora;
  final int minuto;

  RepasoConfig copyWith({bool? activo, int? diaSemana, int? hora, int? minuto}) =>
      RepasoConfig(
        activo: activo ?? this.activo,
        diaSemana: diaSemana ?? this.diaSemana,
        hora: hora ?? this.hora,
        minuto: minuto ?? this.minuto,
      );

  String get horaFormateada =>
      '${hora.toString().padLeft(2, '0')}:${minuto.toString().padLeft(2, '0')}';

  /// Nombre del día ISO (1=lun … 7=dom), en español.
  String get diaNombre => const [
        'Lunes',
        'Martes',
        'Miércoles',
        'Jueves',
        'Viernes',
        'Sábado',
        'Domingo',
      ][(diaSemana - 1).clamp(0, 6)];
}

class RepasoConfigController extends StateNotifier<RepasoConfig> {
  RepasoConfigController(this._repo) : super(const RepasoConfig()) {
    _ready = _cargar();
  }

  final RitualesRepository _repo;
  late final Future<void> _ready;
  Future<void> get ready => _ready;

  Future<void> _cargar() async {
    try {
      final c = await _repo.obtener('repaso');
      if (c != null) {
        state = RepasoConfig(
          activo: c.activo,
          diaSemana: c.diaSemana ?? 7,
          hora: c.hora,
          minuto: c.minuto,
        );
      }
    } catch (_) {
      // Sin red / migración sin aplicar: dejamos el default (ON, dom 20:00).
    }
  }

  Future<void> activar(bool v) async {
    state = state.copyWith(activo: v);
    await _guardar();
  }

  Future<void> cambiarDia(int diaSemana) async {
    state = state.copyWith(diaSemana: diaSemana);
    await _guardar();
  }

  Future<void> cambiarHora(int hora, int minuto) async {
    state = state.copyWith(hora: hora, minuto: minuto);
    await _guardar();
  }

  Future<void> _guardar() async {
    try {
      await _repo.actualizar(
        'repaso',
        activo: state.activo,
        hora: state.hora,
        minuto: state.minuto,
        diaSemana: state.diaSemana,
      );
    } catch (_) {
      // Best-effort: el estado local ya cambió; reintenta en el próximo toque.
    }
  }
}

final repasoConfigProvider =
    StateNotifierProvider<RepasoConfigController, RepasoConfig>((ref) {
  return RepasoConfigController(ref.watch(ritualesRepositoryProvider));
});
