// ignore_for_file: use_null_aware_elements

import '../../../api/matix_client.dart';
import '../../../core/notif_id.dart';
import '../../../core/notificaciones_service.dart';
import '../domain/evaluacion.dart';

class EvaluacionesRepository {
  EvaluacionesRepository(this._client, this._notif);
  final MatixClient _client;
  final NotificacionesService _notif;

  Future<List<Evaluacion>> listar() async {
    final raw = await _client.getList('/api/v1/evaluaciones');
    return raw
        .cast<Map<String, dynamic>>()
        .map(Evaluacion.fromJson)
        .toList(growable: false);
  }

  Future<Evaluacion> crear({
    required String cursoId,
    required String titulo,
    required TipoEvaluacion tipo,
    required DateTime fecha,
    String? descripcion,
    double? peso,
    double? notaMaxima,
    DateTime? recordarEn,
  }) async {
    final body = <String, dynamic>{
      'curso_id': cursoId,
      'titulo': titulo,
      'tipo': tipo.toJson(),
      'fecha': fecha.toUtc().toIso8601String(),
      if (descripcion != null && descripcion.isNotEmpty)
        'descripcion': descripcion,
      if (peso != null) 'peso': peso,
      if (notaMaxima != null) 'nota_maxima': notaMaxima,
      if (recordarEn != null)
        'recordar_en': recordarEn.toUtc().toIso8601String(),
    };
    final j = await _client.post('/api/v1/evaluaciones', body);
    final ev = Evaluacion.fromJson(j);
    await _reprogramarRecordatorio(ev);
    return ev;
  }

  Future<Evaluacion> actualizar(
      String id, Map<String, dynamic> cambios) async {
    final j = await _client.patch('/api/v1/evaluaciones/$id', cambios);
    final ev = Evaluacion.fromJson(j);
    await _reprogramarRecordatorio(ev);
    return ev;
  }

  Future<void> borrar(String id) async {
    await _client.delete('/api/v1/evaluaciones/$id');
    await _notif.cancelar(notifIdDe(id));
  }

  Future<void> _reprogramarRecordatorio(Evaluacion ev) async {
    final nid = notifIdDe(ev.id);
    await _notif.cancelar(nid);
    final r = ev.recordarEn;
    if (r == null) return;
    if (ev.tieneNota) return; // ya pasó y se calificó
    await _notif.pedirPermisos();
    await _notif.programar(
      id: nid,
      titulo: ev.titulo,
      cuerpo: '${ev.tipo.label} próxima',
      cuando: r.toLocal(),
    );
  }
}
