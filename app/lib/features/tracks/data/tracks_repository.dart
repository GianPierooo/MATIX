// ignore_for_file: use_null_aware_elements

import '../../../api/matix_client.dart';
import '../domain/track.dart';

/// Wrapper sobre `/api/v1/tracks` (Fase 2). El tope de 3 activos lo
/// valida el cerebro: activar uno estando en el tope lanza
/// [MatixApiException] con status 409 y un mensaje legible.
class TracksRepository {
  TracksRepository(this._client);
  final MatixClient _client;

  Future<List<Track>> listar() async {
    final raw = await _client.getList('/api/v1/tracks');
    return raw
        .cast<Map<String, dynamic>>()
        .map(Track.fromJson)
        .toList(growable: false);
  }

  Future<Track> crear({
    required String nombre,
    String? descripcion,
    String? bloqueActual,
    EstadoTrack estado = EstadoTrack.activo,
  }) async {
    final body = <String, dynamic>{
      'nombre': nombre,
      'estado': estado.toJson(),
      if (descripcion != null && descripcion.isNotEmpty)
        'descripcion': descripcion,
      if (bloqueActual != null && bloqueActual.isNotEmpty)
        'bloque_actual': bloqueActual,
    };
    final j = await _client.post('/api/v1/tracks', body);
    return Track.fromJson(j);
  }

  Future<Track> actualizar(String id, Map<String, dynamic> cambios) async {
    final j = await _client.patch('/api/v1/tracks/$id', cambios);
    return Track.fromJson(j);
  }

  /// Fija la posición del track. `semana`/`dia` pueden ir en null para
  /// limpiarlas.
  Future<Track> fijarPosicion(
    String id, {
    String? bloqueActual,
    int? semana,
    int? dia,
  }) {
    return actualizar(id, {
      'bloque_actual': bloqueActual,
      'semana': semana,
      'dia': dia,
    });
  }

  Future<Track> activar(String id) => actualizar(id, {'estado': 'activo'});
  Future<Track> pausar(String id) => actualizar(id, {'estado': 'pausado'});

  Future<void> borrar(String id) => _client.delete('/api/v1/tracks/$id');
}
