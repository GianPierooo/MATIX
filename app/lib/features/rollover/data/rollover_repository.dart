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

  /// "Posponer un rato": mueve la tarea al PRÓXIMO hueco real de HOY (antes de
  /// tu ancla de dormir). Reusa el endpoint determinista de rendición de
  /// cuentas (acción `mas_tarde`) — no duplica lógica de ventana útil.
  /// Devuelve `true` si se movió; `false` si ya no quedaba ventana hoy.
  Future<bool> posponerHoy(String tareaId) async {
    final j = await _client.post('/api/v1/push/rendicion-cuentas/accion', {
      'tarea_id': tareaId,
      'accion': 'mas_tarde',
    });
    return j['ok'] == true;
  }
}
