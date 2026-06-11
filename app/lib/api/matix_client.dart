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

  /// Timeout largo para `/api/v1/matix/chat` y otros endpoints de
  /// IA. El chat puede encadenar embed (RAG) + búsqueda + tools +
  /// LLM, fácilmente pasando los 10s del CRUD. 45s cubre con margen
  /// el peor caso típico de Capa 3 (modo tutor: buscar → leer
  /// apunte → resumir + generar preguntas).
  static const _timeoutChat = Duration(seconds: 45);

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

  /// Estado de conexión del agente de la PC (Capa 6), con MOTIVO.
  ///
  /// Distingue tres casos para que la UI nunca quede muda:
  /// - `(conectada: true,  error: null)`  → la PC está conectada al cerebro.
  /// - `(conectada: false, error: null)`  → llegamos al cerebro y dice que NO
  ///   hay agente conectado (arranca el agente en la PC).
  /// - `(conectada: false, error: <txt>)` → no pudimos contactar/entender al
  ///   cerebro (sin red, timeout, 401, 5xx…): el problema NO es el agente.
  ///
  /// Reintenta UNA vez ante un "no" (no ante un error de auth): el WS del agente
  /// puede tener un parpadeo de ~1s al reconectar tras un corte del proxy de
  /// Railway. Dos intentos con ~1.5s de separación absorben ese blip.
  Future<({bool conectada, String? error})> estadoPc() async {
    ({bool conectada, String? error}) ultimo =
        (conectada: false, error: 'No pude comprobar el estado.');
    for (var intento = 0; intento < 2; intento++) {
      try {
        final r = await _conTimeout(
          _inner.get(_uri('/api/v1/agente/estado'), headers: _headers),
          timeout: _timeoutHealth,
        );
        if (r.statusCode == 401 || r.statusCode == 403) {
          // Auth rota: reintentar no ayuda. Cortamos con el motivo claro.
          return (
            conectada: false,
            error: 'La app no está autorizada por el cerebro (HTTP '
                '${r.statusCode}). Revisa la API key.',
          );
        }
        if (r.statusCode != 200) {
          ultimo = (conectada: false, error: 'El cerebro respondió HTTP ${r.statusCode}.');
        } else {
          final j = json.decode(r.body) as Map<String, dynamic>;
          if (j['conectado'] == true) return (conectada: true, error: null);
          ultimo = (conectada: false, error: null); // llegó; agente no conectado
        }
      } catch (e) {
        ultimo = (conectada: false, error: 'No pude contactar a Matix: $e');
      }
      if (intento == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
    }
    return ultimo;
  }

  /// Atajo booleano para el indicador (true = conectada). Delega en `estadoPc`:
  /// una sola fuente de verdad, sin duplicar la lógica de reintento.
  Future<bool> pcConectada() async => (await estadoPc()).conectada;

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
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    // Si el caller no pasa timeout explícito, usamos el largo para
    // rutas de IA (`/matix/...`) y el normal para el resto. Eso
    // cubre `chat`, `transcribir`, `voz` y futuros endpoints
    // pesados sin necesidad de que cada repo lo recuerde.
    final t = timeout ??
        (path.contains('/matix/') ? _timeoutChat : _timeoutNormal);
    final r = await _conTimeout(
      _inner.post(
        _uri(path),
        headers: _headers,
        body: json.encode(body),
      ),
      timeout: t,
    );
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
