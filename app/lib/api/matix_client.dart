import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

/// Excepción de una llamada al cerebro.
///
/// `message` ya viene decodificado del body: si el cerebro devuelve un
/// JSON estilo FastAPI (`{"detail": "..."}` o `{"detail": [...]}`),
/// extraemos `detail` para que el caller pueda mostrarlo directo al
/// usuario sin parsear JSON.
class MatixApiException implements Exception {
  MatixApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => 'MatixApiException($statusCode): $message';
}

/// Extrae un mensaje legible del cuerpo de respuesta de FastAPI.
///
/// - Si el body es `{"detail": "texto"}`, devuelve "texto".
/// - Si el body es `{"detail": [{"msg": "...", "loc": [...]}, ...]}`
///   (formato 422 de Pydantic), une los `msg` con " · ".
/// - Si no se puede parsear, devuelve el body crudo recortado.
String _extraerMensaje(String body) {
  if (body.isEmpty) return '(sin detalle)';
  try {
    final j = json.decode(body);
    if (j is Map && j['detail'] != null) {
      final d = j['detail'];
      if (d is String) return d;
      if (d is List) {
        return d
            .whereType<Map>()
            .map((e) => e['msg']?.toString() ?? e.toString())
            .join(' · ');
      }
    }
  } catch (_) {
    // No es JSON válido: devolvemos el body recortado.
  }
  return body.length > 240 ? '${body.substring(0, 240)}…' : body;
}

/// Cliente HTTP del cerebro.
///
/// Cualquier endpoint de Matix se llama a través de este cliente —
/// la app nunca habla con Supabase directamente.
///
/// Timeouts: cada operación tiene un límite. Si el cerebro está
/// caído o lento, la UI se desbloquea con `MatixApiException(0,
/// 'Sin respuesta del cerebro')` en lugar de colgarse.
class MatixClient {
  MatixClient({http.Client? inner}) : _inner = inner ?? http.Client();

  final http.Client _inner;

  /// Timeout para CRUD normal (lista, get, post, patch, delete).
  static const _timeoutNormal = Duration(seconds: 10);

  /// Timeout más corto para el ping de salud.
  static const _timeoutHealth = Duration(seconds: 5);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (MatixConfig.hasApiKey) 'X-Matix-Key': MatixConfig.apiKey,
      };

  Uri _uri(String path) => Uri.parse('${MatixConfig.apiUrl}$path');

  /// Envuelve un `Future<http.Response>` con timeout y traduce el
  /// `TimeoutException` a `MatixApiException` para que la UI solo
  /// tenga que manejar un tipo de error.
  Future<http.Response> _conTimeout(
    Future<http.Response> req, {
    Duration timeout = _timeoutNormal,
  }) async {
    try {
      return await req.timeout(timeout);
    } on Exception catch (e) {
      throw MatixApiException(0, 'Sin respuesta del cerebro ($e)');
    }
  }

  /// Ping al endpoint `/health` del cerebro. Devuelve el cuerpo decodificado.
  Future<Map<String, dynamic>> health() async {
    final r = await _conTimeout(
      _inner.get(_uri('/health')),
      timeout: _timeoutHealth,
    );
    if (r.statusCode != 200) {
      throw MatixApiException(r.statusCode, _extraerMensaje(r.body));
    }
    return json.decode(r.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> getList(String path) async {
    final r = await _conTimeout(_inner.get(_uri(path), headers: _headers));
    if (r.statusCode != 200) {
      throw MatixApiException(r.statusCode, _extraerMensaje(r.body));
    }
    return json.decode(r.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> getOne(String path) async {
    final r = await _conTimeout(_inner.get(_uri(path), headers: _headers));
    if (r.statusCode != 200) {
      throw MatixApiException(r.statusCode, _extraerMensaje(r.body));
    }
    return json.decode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final r = await _conTimeout(_inner.post(
      _uri(path),
      headers: _headers,
      body: json.encode(body),
    ));
    if (r.statusCode != 201 && r.statusCode != 200) {
      throw MatixApiException(r.statusCode, _extraerMensaje(r.body));
    }
    return json.decode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    final r = await _conTimeout(_inner.patch(
      _uri(path),
      headers: _headers,
      body: json.encode(body),
    ));
    if (r.statusCode != 200) {
      throw MatixApiException(r.statusCode, _extraerMensaje(r.body));
    }
    return json.decode(r.body) as Map<String, dynamic>;
  }

  Future<void> delete(String path) async {
    final r = await _conTimeout(_inner.delete(_uri(path), headers: _headers));
    if (r.statusCode != 204) {
      throw MatixApiException(r.statusCode, _extraerMensaje(r.body));
    }
  }

  void close() => _inner.close();
}
