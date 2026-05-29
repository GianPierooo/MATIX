import '../../../api/matix_client.dart';
import '../domain/tarea_propuesta.dart';

/// Llama al cerebro para convertir el texto del OCR (ya corregido por
/// el usuario en 7-A) en tareas propuestas (Capa 7-B).
///
/// SOLO viaja el texto: la imagen se quedó en el teléfono. El cerebro
/// NO persiste nada — devuelve candidatas que el usuario revisa y
/// confirma antes de crearse con el CRUD de siempre.
class ExtraccionTareasRepository {
  ExtraccionTareasRepository(this._client);
  final MatixClient _client;

  /// Manda `texto` a `/matix/extraer-tareas` y devuelve las tareas
  /// propuestas. Lista vacía es un resultado válido (el texto no tenía
  /// acciones claras), no un error. Cualquier fallo de red o del
  /// modelo se propaga como [MatixApiException] para que el caller lo
  /// muestre y ofrezca reintento.
  Future<List<TareaPropuesta>> extraer(String texto) async {
    final j = await _client.post(
      '/api/v1/matix/extraer-tareas',
      {'texto': texto},
    );
    final crudas = (j['tareas'] as List?) ?? const [];
    return crudas
        .cast<Map<String, dynamic>>()
        .map(TareaPropuesta.fromCerebro)
        .where((t) => t.titulo.isNotEmpty)
        .toList(growable: false);
  }
}
