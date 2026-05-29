// ignore_for_file: use_null_aware_elements

import '../../../api/matix_client.dart';
import '../../../core/notif_id.dart';
import '../../../core/notificaciones_service.dart';
import '../domain/evento.dart';
import '../domain/recordatorio_evento.dart';

/// Wrapper sobre `/api/v1/eventos`. Mantiene sincronizadas las
/// notificaciones locales con `recordar_en` (mismo patrón que
/// `TareasRepository`).
class EventosRepository {
  EventosRepository(this._client, this._notif);
  final MatixClient _client;
  final NotificacionesService _notif;

  Future<List<Evento>> listar() async {
    final raw = await _client.getList('/api/v1/eventos');
    return raw
        .cast<Map<String, dynamic>>()
        .map(Evento.fromJson)
        .toList(growable: false);
  }

  Future<List<Evento>> listarPapelera() async {
    final raw = await _client.getList('/api/v1/eventos?papelera=true');
    return raw
        .cast<Map<String, dynamic>>()
        .map(Evento.fromJson)
        .toList(growable: false);
  }

  Future<Evento> obtener(String id) async {
    final j = await _client.getOne('/api/v1/eventos/$id');
    return Evento.fromJson(j);
  }

  Future<Evento> crear({
    required String titulo,
    String? descripcion,
    required DateTime iniciaEn,
    DateTime? terminaEn,
    bool todoElDia = false,
    String? ubicacion,
    String? cursoId,
    String? proyectoId,
    String? color,
    int? recordatorioOffsetMin,
  }) async {
    // El offset es la fuente de verdad; `recordar_en` se deriva como
    // espejo absoluto (inicia − offset) para lectores legados.
    final recordarEn = momentoRecordatorio(iniciaEn, recordatorioOffsetMin);
    final body = <String, dynamic>{
      'titulo': titulo,
      'inicia_en': iniciaEn.toUtc().toIso8601String(),
      'todo_el_dia': todoElDia,
      if (descripcion != null && descripcion.isNotEmpty)
        'descripcion': descripcion,
      if (terminaEn != null)
        'termina_en': terminaEn.toUtc().toIso8601String(),
      if (ubicacion != null && ubicacion.isNotEmpty) 'ubicacion': ubicacion,
      if (cursoId != null) 'curso_id': cursoId,
      if (proyectoId != null) 'proyecto_id': proyectoId,
      if (color != null) 'color': color,
      if (recordatorioOffsetMin != null)
        'recordatorio_offset_min': recordatorioOffsetMin,
      if (recordarEn != null)
        'recordar_en': recordarEn.toUtc().toIso8601String(),
    };
    final j = await _client.post('/api/v1/eventos', body);
    final e = Evento.fromJson(j);
    await _reprogramarRecordatorio(e);
    return e;
  }

  Future<Evento> actualizar(String id, Map<String, dynamic> cambios) async {
    final j = await _client.patch('/api/v1/eventos/$id', cambios);
    final e = Evento.fromJson(j);
    await _reprogramarRecordatorio(e);
    return e;
  }

  Future<void> borrar(String id) async {
    // Soft delete (Capa 2 Paso 5).
    await _client.delete('/api/v1/eventos/$id');
    await _notif.cancelar(notifIdDe(id));
  }

  Future<Evento> restaurar(String id) async {
    final j = await _client.post('/api/v1/eventos/$id/restaurar', const {});
    final e = Evento.fromJson(j);
    await _reprogramarRecordatorio(e);
    return e;
  }

  Future<void> borrarPermanente(String id) async {
    await _client.delete('/api/v1/eventos/$id/permanente');
    await _notif.cancelar(notifIdDe(id));
  }

  Future<void> _reprogramarRecordatorio(Evento e) async {
    final nid = notifIdDe(e.id);
    await _notif.cancelar(nid);
    // El offset manda: si el evento (o su recordatorio) ya pasó,
    // `momentoRecordatorio` da un instante pasado y `programar` no agenda.
    final cuando = momentoRecordatorio(e.iniciaEn.toLocal(), e.recordatorioOffsetMin);
    if (cuando == null) return;
    await _notif.pedirPermisos();
    await _notif.programar(
      id: nid,
      titulo: e.titulo,
      cuerpo: e.ubicacion?.isNotEmpty == true
          ? e.ubicacion!
          : 'Tu evento está por empezar.',
      cuando: cuando,
      exacto: true,
      payload: 'evento:${e.id}',
    );
  }
}
