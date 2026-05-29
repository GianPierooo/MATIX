import '../../../api/matix_client.dart';
import '../../tareas/domain/tarea.dart';

/// Pide a Matix (cerebro → OpenAI) una duración estimada por tarea, para
/// que el planificador sepa de qué tamaño es cada bloque (Urgencia-3).
///
/// Devuelve un mapa `{tareaId: minutos}`. Las tareas que el modelo no
/// pudo dimensionar se omiten — el planificador les aplica un default.
class DuracionesRepository {
  DuracionesRepository(this._client);
  final MatixClient _client;

  Future<Map<String, int>> estimar(List<Tarea> tareas) async {
    if (tareas.isEmpty) return const {};
    final j = await _client.post('/api/v1/matix/estimar-duraciones', {
      'tareas': [
        for (final t in tareas) {'id': t.id, 'titulo': t.titulo},
      ],
    });
    final crudas = (j['duraciones'] as List?) ?? const [];
    final out = <String, int>{};
    for (final d in crudas.cast<Map<String, dynamic>>()) {
      final id = d['tarea_id']?.toString();
      final min = d['minutos'];
      if (id != null && min is num) out[id] = min.toInt();
    }
    return out;
  }
}
