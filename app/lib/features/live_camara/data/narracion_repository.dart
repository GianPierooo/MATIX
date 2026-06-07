import '../../../api/matix_client.dart';

/// Manda un frame muestreado al cerebro y devuelve la narración corta (vacía si
/// no hay nada nuevo). El muestreo y los topes ya los aplicó la app: acá solo
/// viaja lo que pasó el filtro.
class NarracionRepository {
  NarracionRepository(this._client);
  final MatixClient _client;

  Future<String> narrarFrame(String imagenDataUrl, {String? previa}) async {
    // Timeout ACOTADO: el cerebro ya tiene timeout agresivo por proveedor y
    // failover rápido, así que un frame jamás debería tardar 20s. Si igual
    // cuelga, lo soltamos y el siguiente frame (más fresco) lo reintenta — la
    // cámara va en tiempo real, no se queda pegada esperando.
    final j = await _client.post(
      '/api/v1/matix/narrar-frame',
      {'imagen': imagenDataUrl, 'narracion_previa': ?previa},
      timeout: const Duration(seconds: 12),
    );
    return (j['narracion'] as String?)?.trim() ?? '';
  }
}
