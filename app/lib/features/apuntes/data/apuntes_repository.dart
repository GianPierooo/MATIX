// ignore_for_file: use_null_aware_elements

import '../../../api/matix_client.dart';
import '../domain/apunte.dart';

class ApuntesRepository {
  ApuntesRepository(this._client);
  final MatixClient _client;

  Future<List<Apunte>> listar() async {
    final raw = await _client.getList('/api/v1/apuntes');
    return raw
        .cast<Map<String, dynamic>>()
        .map(Apunte.fromJson)
        .toList(growable: false);
  }

  Future<List<Apunte>> listarPapelera() async {
    final raw = await _client.getList('/api/v1/apuntes?papelera=true');
    return raw
        .cast<Map<String, dynamic>>()
        .map(Apunte.fromJson)
        .toList(growable: false);
  }

  Future<Apunte> obtener(String id) async {
    final j = await _client.getOne('/api/v1/apuntes/$id');
    return Apunte.fromJson(j);
  }

  Future<Apunte> crear({
    required String titulo,
    String contenido = '',
    String? cursoId,
    String? proyectoId,
    List<String> etiquetas = const [],
  }) async {
    final body = <String, dynamic>{
      'titulo': titulo,
      'contenido': contenido,
      'etiquetas': etiquetas,
      if (cursoId != null) 'curso_id': cursoId,
      if (proyectoId != null) 'proyecto_id': proyectoId,
    };
    final j = await _client.post('/api/v1/apuntes', body);
    return Apunte.fromJson(j);
  }

  Future<Apunte> actualizar(String id, Map<String, dynamic> cambios) async {
    final j = await _client.patch('/api/v1/apuntes/$id', cambios);
    return Apunte.fromJson(j);
  }

  /// Soft delete (Capa 2 Paso 5): manda a la papelera.
  Future<void> borrar(String id) => _client.delete('/api/v1/apuntes/$id');

  Future<Apunte> restaurar(String id) async {
    final j = await _client.post('/api/v1/apuntes/$id/restaurar', const {});
    return Apunte.fromJson(j);
  }

  Future<void> borrarPermanente(String id) =>
      _client.delete('/api/v1/apuntes/$id/permanente');
}
