import '../../../api/matix_client.dart';

/// Manda un frame muestreado al cerebro y devuelve la narración corta (vacía si
/// no hay nada nuevo). El muestreo y los topes ya los aplicó la app: acá solo
/// viaja lo que pasó el filtro.
class NarracionRepository {
  NarracionRepository(this._client);
  final MatixClient _client;

  Future<String> narrarFrame(String imagenDataUrl, {String? previa}) async {
    final j = await _client.post(
      '/api/v1/matix/narrar-frame',
      {'imagen': imagenDataUrl, 'narracion_previa': ?previa},
      timeout: const Duration(seconds: 20),
    );
    return (j['narracion'] as String?)?.trim() ?? '';
  }
}
