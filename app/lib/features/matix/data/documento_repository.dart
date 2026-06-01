import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../api/matix_client.dart';
import '../../../config.dart';

/// Texto extraído de un documento adjunto (lo que devuelve el cerebro).
class DocumentoExtraido {
  const DocumentoExtraido({
    required this.nombre,
    required this.texto,
    required this.caracteres,
    required this.truncado,
  });

  final String nombre;
  final String texto;
  final int caracteres;

  /// `true` si el cerebro recortó el documento por largo (se avisa en la UI).
  final bool truncado;

  factory DocumentoExtraido.fromJson(Map<String, dynamic> j) =>
      DocumentoExtraido(
        nombre: (j['nombre'] as String?) ?? 'documento',
        texto: (j['texto'] as String?) ?? '',
        caracteres: (j['caracteres'] as int?) ?? 0,
        truncado: (j['truncado'] as bool?) ?? false,
      );
}

/// Wrapper sobre `POST /api/v1/matix/extraer-documento`.
///
/// Sube el archivo por multipart (igual que `MatixTranscribirRepository` con
/// el audio) y devuelve el texto. La extracción de PDF/DOCX vive en el cerebro
/// (reusa la misma librería que la ingestión de material); la app solo sube el
/// archivo y recibe el texto, que luego manda como contexto del chat.
class DocumentoRepository {
  DocumentoRepository({http.Client? inner}) : _inner = inner ?? http.Client();

  final http.Client _inner;

  Future<DocumentoExtraido> extraer(File archivo, {required String nombre}) async {
    final uri = Uri.parse('${MatixConfig.apiUrl}/api/v1/matix/extraer-documento');
    final req = http.MultipartRequest('POST', uri);
    if (MatixConfig.hasApiKey) {
      req.headers['X-Matix-Key'] = MatixConfig.apiKey;
    }
    req.files.add(
      await http.MultipartFile.fromPath('file', archivo.path, filename: nombre),
    );

    final streamed = await _inner.send(req).timeout(const Duration(seconds: 60));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) {
      throw MatixApiException(resp.statusCode, _extraerMensaje(resp.body));
    }
    return DocumentoExtraido.fromJson(
      json.decode(resp.body) as Map<String, dynamic>,
    );
  }

  void close() => _inner.close();
}

/// Misma extracción de mensaje de error que `MatixClient`.
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
