import '../../../api/matix_client.dart';
import '../domain/destino_ocr.dart';

/// Llama al cerebro para clasificar el texto de una captura (OCR
/// on-device) en uno de los tres destinos de la cámara inteligente:
/// tareas, eventos o apunte.
///
/// SOLO viaja el texto: la imagen se quedó en el teléfono. El cerebro
/// NO persiste nada — solo sugiere a qué flujo mandar la captura. Ante
/// duda devuelve `apunte`, y cualquier valor inesperado también cae a
/// [DestinoOcr.apunte] (ver [destinoDesdeTipo]). La clasificación es
/// best-effort: el caller la envuelve en try/catch y, si falla, sigue
/// con el catch-all — la captura nunca se queda atascada.
class ClasificacionRepository {
  ClasificacionRepository(this._client);
  final MatixClient _client;

  Future<DestinoOcr> clasificar(String texto) async {
    final j = await _client.post(
      '/api/v1/matix/clasificar-captura',
      {'texto': texto},
    );
    return destinoDesdeTipo(j['tipo'] as String?);
  }
}
