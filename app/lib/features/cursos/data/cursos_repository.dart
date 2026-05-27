// ignore_for_file: use_null_aware_elements

import '../../../api/matix_client.dart';
import '../domain/curso.dart';
import '../domain/sesion_clase.dart';

class CursosRepository {
  CursosRepository(this._client);
  final MatixClient _client;

  Future<List<Curso>> listar() async {
    final raw = await _client.getList('/api/v1/cursos');
    return raw
        .cast<Map<String, dynamic>>()
        .map(Curso.fromJson)
        .toList(growable: false);
  }

  Future<Curso> obtener(String id) async {
    final j = await _client.getOne('/api/v1/cursos/$id');
    return Curso.fromJson(j);
  }

  Future<Curso> crear({
    required String nombre,
    String? profesor,
    String? color,
  }) async {
    final body = <String, dynamic>{
      'nombre': nombre,
      if (profesor != null && profesor.isNotEmpty) 'profesor': profesor,
      if (color != null) 'color': color,
    };
    final j = await _client.post('/api/v1/cursos', body);
    return Curso.fromJson(j);
  }

  Future<void> borrar(String id) => _client.delete('/api/v1/cursos/$id');

  Future<List<SesionClase>> listarSesiones() async {
    final raw = await _client.getList('/api/v1/sesiones-clase');
    return raw
        .cast<Map<String, dynamic>>()
        .map(SesionClase.fromJson)
        .toList(growable: false);
  }

  Future<SesionClase> crearSesion({
    required String cursoId,
    required int diaSemana,
    required String horaInicio,
    required String horaFin,
    String? ubicacion,
  }) async {
    final body = <String, dynamic>{
      'curso_id': cursoId,
      'dia_semana': diaSemana,
      'hora_inicio': horaInicio,
      'hora_fin': horaFin,
      if (ubicacion != null && ubicacion.isNotEmpty) 'ubicacion': ubicacion,
    };
    final j = await _client.post('/api/v1/sesiones-clase', body);
    return SesionClase.fromJson(j);
  }

  Future<void> borrarSesion(String id) =>
      _client.delete('/api/v1/sesiones-clase/$id');
}
