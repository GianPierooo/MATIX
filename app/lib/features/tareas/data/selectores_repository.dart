import '../../../api/matix_client.dart';
import '../domain/selectores.dart';

/// Carga las listas que alimentan los dropdowns de "Nueva Tarea":
/// categorías, cursos y proyectos.
class SelectoresRepository {
  SelectoresRepository(this._client);
  final MatixClient _client;

  Future<List<CategoriaRef>> categorias() async {
    final raw = await _client.getList('/api/v1/categorias');
    return raw
        .cast<Map<String, dynamic>>()
        .map(CategoriaRef.fromJson)
        .toList(growable: false);
  }

  Future<List<CursoRef>> cursos() async {
    final raw = await _client.getList('/api/v1/cursos');
    return raw
        .cast<Map<String, dynamic>>()
        .map(CursoRef.fromJson)
        .toList(growable: false);
  }

  Future<List<ProyectoRef>> proyectos() async {
    final raw = await _client.getList('/api/v1/proyectos');
    return raw
        .cast<Map<String, dynamic>>()
        .map(ProyectoRef.fromJson)
        .toList(growable: false);
  }
}
