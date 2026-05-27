// ignore_for_file: use_null_aware_elements

import 'package:intl/intl.dart';

import '../../../api/matix_client.dart';
import '../domain/cierre_dia.dart';

class CierresRepository {
  CierresRepository(this._client);
  final MatixClient _client;

  Future<List<CierreDia>> listar() async {
    final raw = await _client.getList('/api/v1/cierres_dia');
    return raw
        .cast<Map<String, dynamic>>()
        .map(CierreDia.fromJson)
        .toList(growable: false);
  }

  Future<CierreDia?> obtenerDe(DateTime fecha) async {
    final f = DateFormat('yyyy-MM-dd').format(fecha);
    final raw = await _client.getList('/api/v1/cierres_dia?fecha=$f');
    if (raw.isEmpty) return null;
    return CierreDia.fromJson(raw.first as Map<String, dynamic>);
  }

  /// Crea o sobreescribe el cierre del día. El cerebro hace el UPSERT.
  Future<CierreDia> guardar({
    required DateTime fecha,
    required List<String> items,
    String? notaExtra,
  }) async {
    final body = <String, dynamic>{
      'fecha': DateFormat('yyyy-MM-dd').format(fecha),
      'items': items,
      if (notaExtra != null && notaExtra.isNotEmpty) 'nota_extra': notaExtra,
    };
    final j = await _client.post('/api/v1/cierres_dia', body);
    return CierreDia.fromJson(j);
  }

  Future<void> borrar(String id) =>
      _client.delete('/api/v1/cierres_dia/$id');
}
