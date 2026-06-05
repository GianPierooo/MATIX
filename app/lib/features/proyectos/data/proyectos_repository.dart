// ignore_for_file: use_null_aware_elements

import '../../../api/matix_client.dart';
import '../domain/proyecto.dart';

/// Wrapper sobre `/api/v1/proyectos`. El tope de 3 activos, la
/// coherencia acción-siguiente y la gestión de `inactivo_desde` /
/// `ultima_actividad_en` viven en el cerebro — el repo solo traduce
/// JSON ↔ entity y propaga los 409.
class ProyectosRepository {
  ProyectosRepository(this._client);
  final MatixClient _client;

  Future<List<Proyecto>> listar() async {
    final raw = await _client.getList('/api/v1/proyectos');
    return raw
        .cast<Map<String, dynamic>>()
        .map(Proyecto.fromJson)
        .toList(growable: false);
  }

  Future<Proyecto> obtener(String id) async {
    final j = await _client.getOne('/api/v1/proyectos/$id');
    return Proyecto.fromJson(j);
  }

  /// Descomposición (árbol) del proyecto: fases → pasos, para el detalle.
  Future<List<NodoArbol>> arbol(String id) async {
    final j = await _client.getOne('/api/v1/proyectos/$id/arbol');
    return (j['nodos'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(NodoArbol.fromJson)
        .toList(growable: false);
  }

  Future<Proyecto> crear({
    required String nombre,
    String? descripcion,
    EstadoProyecto estado = EstadoProyecto.activo,
    int? prioridad,
    String? lineaMeta,
    String? tareaSiguienteId,
    String? color,
  }) async {
    final body = <String, dynamic>{
      'nombre': nombre,
      'estado': estado.toJson(),
      if (descripcion != null && descripcion.isNotEmpty)
        'descripcion': descripcion,
      if (prioridad != null) 'prioridad': prioridad,
      if (lineaMeta != null && lineaMeta.isNotEmpty) 'linea_meta': lineaMeta,
      if (tareaSiguienteId != null) 'tarea_siguiente_id': tareaSiguienteId,
      if (color != null) 'color': color,
    };
    final j = await _client.post('/api/v1/proyectos', body);
    return Proyecto.fromJson(j);
  }

  Future<Proyecto> actualizar(String id, Map<String, dynamic> cambios) async {
    final j = await _client.patch('/api/v1/proyectos/$id', cambios);
    return Proyecto.fromJson(j);
  }

  Future<Proyecto> cambiarEstado(String id, EstadoProyecto nuevo) =>
      actualizar(id, {'estado': nuevo.toJson()});

  Future<void> borrar(String id) =>
      _client.delete('/api/v1/proyectos/$id');
}
