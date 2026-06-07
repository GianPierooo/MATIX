import '../../../api/matix_client.dart';
import '../domain/plan_dia.dart';

/// Acceso al plan del día (capa de horario) del cerebro.
class HorarioRepository {
  HorarioRepository(this._client);
  final MatixClient _client;

  /// Trae el plan del día. `desdeAhora` = replan del resto del día.
  Future<PlanDia> cargar({bool desdeAhora = false}) async {
    final j = desdeAhora
        ? await _client.post('/api/v1/horario/replanificar', const {})
        : await _client.getOne('/api/v1/horario');
    return PlanDia.fromJson(j);
  }

  /// "Me acabo de levantar": registra el ancla de despertar de HOY (sin tocar
  /// la rutina estándar) y devuelve el plan recalculado desde esa hora. 100%
  /// determinista en el cerebro (sin LLM): las cosas de hoy aparecen al toque.
  Future<PlanDia> despertar() async {
    final j = await _client.post('/api/v1/horario/despertar', const {});
    return PlanDia.fromJson((j['plan'] as Map).cast<String, dynamic>());
  }

  /// Marca un bloque planificado como hecho (cierra nodo y/o tarea).
  Future<void> completar({String? tareaId, String? nodoId}) async {
    await _client.post('/api/v1/horario/bloque/completar', {
      'tarea_id': ?tareaId,
      'nodo_id': ?nodoId,
    });
  }

  /// Salta un bloque del set (no hoy, sin culpa).
  Future<void> saltar(String setItemId) async {
    await _client.post('/api/v1/horario/bloque/saltar', {'set_item_id': setItemId});
  }

  /// Empuja los bloques tentativos (con sus horas, incluidas ediciones) al
  /// calendario. Idempotente del lado del cerebro. Devuelve {creados, omitidos}.
  Future<Map<String, dynamic>> aCalendario(List<BloquePlan> tentativos) {
    return _client.post('/api/v1/horario/calendario', {
      'bloques': [
        for (final b in tentativos)
          {'titulo': b.titulo, 'inicio': b.inicio, 'fin': b.fin},
      ],
    });
  }
}
