import '../../../api/matix_client.dart';
import '../domain/evento_propuesto.dart';

/// Llama al cerebro para convertir el texto de un sílabo/horario (OCR ya
/// corregido) en eventos propuestos (Cámara · sílabo).
///
/// SOLO viaja el texto: la imagen se quedó en el teléfono. El cerebro
/// NO persiste nada — devuelve candidatos (clases recurrentes + fechas
/// únicas) que el usuario revisa y confirma antes de crearse con el
/// calendario de siempre.
class ExtraccionEventosRepository {
  ExtraccionEventosRepository(this._client);
  final MatixClient _client;

  Future<List<EventoPropuesto>> extraer(String texto) async {
    final j = await _client.post(
      '/api/v1/matix/extraer-eventos',
      {'texto': texto},
    );
    final crudos = (j['eventos'] as List?) ?? const [];
    return crudos
        .cast<Map<String, dynamic>>()
        .map(EventoPropuesto.fromCerebro)
        .where((e) => e.titulo.isNotEmpty)
        .toList(growable: false);
  }
}
