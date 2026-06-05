import '../../../api/matix_client.dart';
import '../domain/rollover.dart';

/// Acceso al ROLLOVER del cerebro: trae las propuestas de reprogramación de lo
/// no cumplido (+ flag de sobrecarga) y aplica la decisión del usuario. Reusa el
/// planificador del horario del lado del cerebro; acá solo es transporte.
class RolloverRepository {
  RolloverRepository(this._client);
  final MatixClient _client;

  /// Propuestas + sobrecarga. Determinístico (el cerebro recalcula al vuelo).
  Future<RolloverData> cargar() async {
    final j = await _client.getOne('/api/v1/rollover');
    return RolloverData.fromJson(j);
  }

  /// Aplica la decisión sobre una tarea no cumplida.
  Future<void> decidir(String tareaId, DecisionRollover decision) async {
    await _client.post('/api/v1/rollover/decidir', {
      'tarea_id': tareaId,
      'decision': decision.id,
    });
  }
}
