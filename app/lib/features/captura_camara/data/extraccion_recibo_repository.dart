import '../../../api/matix_client.dart';
import '../domain/recibo_propuesto.dart';

/// Llama al cerebro para convertir el texto de un recibo (OCR ya
/// corregido) en un gasto propuesto (Finanzas-2).
///
/// SOLO viaja el texto: la imagen se quedó en el teléfono. El cerebro NO
/// persiste nada — devuelve un candidato que el usuario revisa y guarda
/// en Finanzas. Cualquier fallo se propaga como [MatixApiException].
class ExtraccionReciboRepository {
  ExtraccionReciboRepository(this._client);
  final MatixClient _client;

  Future<ReciboPropuesto> extraer(String texto) async {
    final j = await _client.post(
      '/api/v1/matix/extraer-recibo',
      {'texto': texto},
    );
    final crudo = (j['recibo'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ReciboPropuesto.fromCerebro(crudo);
  }
}
