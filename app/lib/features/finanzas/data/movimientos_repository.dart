import 'package:intl/intl.dart';

import '../../../api/matix_client.dart';
import '../domain/movimiento.dart';

/// Llama al cerebro para el CRUD de movimientos (Finanzas-1). La app
/// nunca habla con Supabase directo: todo pasa por `/api/v1/movimientos`.
class MovimientosRepository {
  MovimientosRepository(this._client);
  final MatixClient _client;

  static final _fechaFmt = DateFormat('yyyy-MM-dd');

  Future<List<Movimiento>> listar() async {
    final raw = await _client.getList('/api/v1/movimientos');
    return raw
        .cast<Map<String, dynamic>>()
        .map(Movimiento.fromJson)
        .toList(growable: false);
  }

  Future<Movimiento> obtener(String id) async {
    final j = await _client.getOne('/api/v1/movimientos/$id');
    return Movimiento.fromJson(j);
  }

  Future<Movimiento> crear({
    required TipoMovimiento tipo,
    required double monto,
    required String categoria,
    required DateTime fecha,
    String nota = '',
  }) async {
    final body = <String, dynamic>{
      'tipo': tipo.apiValue,
      'monto': monto,
      'categoria': categoria,
      'fecha': _fechaFmt.format(fecha),
      'nota': nota,
    };
    final j = await _client.post('/api/v1/movimientos', body);
    return Movimiento.fromJson(j);
  }

  Future<Movimiento> actualizar({
    required String id,
    required TipoMovimiento tipo,
    required double monto,
    required String categoria,
    required DateTime fecha,
    String nota = '',
  }) async {
    final body = <String, dynamic>{
      'tipo': tipo.apiValue,
      'monto': monto,
      'categoria': categoria,
      'fecha': _fechaFmt.format(fecha),
      'nota': nota,
    };
    final j = await _client.patch('/api/v1/movimientos/$id', body);
    return Movimiento.fromJson(j);
  }

  Future<void> borrar(String id) => _client.delete('/api/v1/movimientos/$id');
}
