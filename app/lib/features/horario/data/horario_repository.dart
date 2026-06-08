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

  /// Lista las notis proactivas programadas para el RESTO de HOY (resumen
  /// matutino + pre-actividad + nudges del próximo bloque). Determinista en el
  /// cerebro (plantilla, cero LLM). La app las mete al scheduler local con
  /// `NotificacionesService.programar`. Re-pedirlo es idempotente por
  /// `dedup_key` (el servicio cancela las anteriores antes de programar).
  Future<Map<String, dynamic>> traerNotisProgramadas() async {
    return await _client.getOne('/api/v1/horario/notis-programadas');
  }

  /// AGENDA los bloques tentativos como TAREAS del hub (camino canónico). Manda
  /// los ids para enganchar al modelo Tarea↔bloque: si el bloque ya viene de una
  /// tarea/set/nodo se agenda ESA, si no se crea una tarea — NUNCA un evento.
  /// Idempotente del lado del cerebro. Devuelve {agendadas, omitidas}.
  Future<Map<String, dynamic>> agendar(List<BloquePlan> tentativos) {
    return _client.post('/api/v1/horario/agendar', {
      'bloques': [
        for (final b in tentativos)
          {
            'titulo': b.titulo,
            'inicio': b.inicio,
            'fin': b.fin,
            'tipo': b.tipo,
            'tarea_id': ?b.tareaId,
            'nodo_id': ?b.nodoId,
            'set_item_id': ?b.setItemId,
          },
      ],
    });
  }
}
