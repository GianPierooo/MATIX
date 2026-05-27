import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../api/matix_client.dart';
import '../../../config.dart';

/// Wrapper sobre `POST /api/v1/matix/transcribir`.
///
/// Necesita subir multipart, así que no usa los métodos JSON de
/// `MatixClient` — habla directo con `http.MultipartRequest`. La
/// API key sigue inyectándose como header `X-Matix-Key`.
///
/// La app NUNCA habla con OpenAI: el cerebro guarda la
/// `OPENAI_API_KEY` y llama a Whisper desde ahí.
class MatixTranscribirRepository {
  MatixTranscribirRepository({http.Client? inner})
      : _inner = inner ?? http.Client();

  final http.Client _inner;

  /// Sube el archivo `audio` y devuelve el texto transcrito.
  ///
  /// Lanza `MatixApiException` con el `statusCode` del cerebro si
  /// algo falla (sin OPENAI_API_KEY → 503, audio vacío → 400, audio
  /// muy grande → 413, Whisper rechaza → 502).
  Future<String> transcribir(File audio) async {
    final uri = Uri.parse('${MatixConfig.apiUrl}/api/v1/matix/transcribir');
    final req = http.MultipartRequest('POST', uri);
    if (MatixConfig.hasApiKey) {
      req.headers['X-Matix-Key'] = MatixConfig.apiKey;
    }
    req.files.add(
      await http.MultipartFile.fromPath(
        'file',
        audio.path,
        filename: 'matix-${DateTime.now().millisecondsSinceEpoch}.m4a',
      ),
    );

    // Whisper puede tardar — damos margen amplio sin colgar la UI
    // para siempre.
    final streamed = await _inner.send(req).timeout(
          const Duration(seconds: 60),
        );
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode != 200) {
      throw MatixApiException(
        resp.statusCode,
        _extraerMensaje(resp.body),
      );
    }
    final body = json.decode(resp.body) as Map<String, dynamic>;
    return (body['texto'] as String?) ?? '';
  }

  void close() => _inner.close();
}

/// Misma extracción que `MatixClient`: si FastAPI devuelve
/// `{"detail": "..."}`, sacamos `detail`; si es la lista de
/// validación 422, juntamos los `msg`. Si no, mostramos un
/// recorte del body.
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
    // body no es JSON
  }
  return body.length > 240 ? '${body.substring(0, 240)}…' : body;
}
