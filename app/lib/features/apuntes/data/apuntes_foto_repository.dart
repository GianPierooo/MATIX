import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../api/matix_client.dart';
import '../../../config.dart';
import '../domain/apunte.dart';

/// Resultado del endpoint `POST /api/v1/apuntes/desde-foto`
/// (Capa 7 · Paso 1).
///
/// El apunte siempre se crea — `ocrOk` indica si la transcripción
/// salió bien. Si `false`, el contenido viene vacío y `mensajeOcr`
/// trae texto legible que la UI muestra como warning.
class ApunteDesdeFoto {
  const ApunteDesdeFoto({
    required this.apunte,
    required this.ocrOk,
    this.mensajeOcr,
  });

  final Apunte apunte;
  final bool ocrOk;
  final String? mensajeOcr;
}

/// Wrapper sobre `POST /api/v1/apuntes/desde-foto`.
///
/// Mismo patrón que `MatixTranscribirRepository`: multipart directo
/// con `http.MultipartRequest` porque `MatixClient` solo cubre JSON.
/// La `X-Matix-Key` viaja como header.
class ApuntesFotoRepository {
  ApuntesFotoRepository({http.Client? inner})
      : _inner = inner ?? http.Client();

  final http.Client _inner;

  /// Sube `imagen` al cerebro y devuelve el apunte creado + el
  /// resultado del OCR.
  ///
  /// Lanza `MatixApiException` si la subida falla (storage caído,
  /// API key inválida, imagen rechazada). Si el OCR falla pero la
  /// imagen subió OK, no lanza — devuelve `ocrOk: false`.
  Future<ApunteDesdeFoto> subir(
    File imagen, {
    String? titulo,
    String? cursoId,
    String? proyectoId,
    String? cuadernoId,
    List<String> etiquetas = const [],
  }) async {
    final uri = Uri.parse('${MatixConfig.apiUrl}/api/v1/apuntes/desde-foto');
    final req = http.MultipartRequest('POST', uri);
    if (MatixConfig.hasApiKey) {
      req.headers['X-Matix-Key'] = MatixConfig.apiKey;
    }
    req.files.add(
      await http.MultipartFile.fromPath(
        'file',
        imagen.path,
        filename:
            'matix-foto-${DateTime.now().millisecondsSinceEpoch}.jpg',
      ),
    );
    if (titulo != null && titulo.isNotEmpty) {
      req.fields['titulo'] = titulo;
    }
    if (cursoId != null) req.fields['curso_id'] = cursoId;
    if (proyectoId != null) req.fields['proyecto_id'] = proyectoId;
    if (cuadernoId != null) req.fields['cuaderno_id'] = cuadernoId;
    if (etiquetas.isNotEmpty) {
      req.fields['etiquetas'] = etiquetas.join(',');
    }

    // OpenAI vision puede tardar varios segundos en imágenes
    // grandes. Damos margen pero no infinito.
    final streamed = await _inner.send(req).timeout(
          const Duration(seconds: 90),
        );
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode != 201) {
      throw MatixApiException(
        resp.statusCode,
        _extraerMensaje(resp.body),
      );
    }
    final body = json.decode(resp.body) as Map<String, dynamic>;
    return ApunteDesdeFoto(
      apunte: Apunte.fromJson(body),
      ocrOk: body['ocr_ok'] as bool? ?? true,
      mensajeOcr: body['mensaje_ocr'] as String?,
    );
  }

  void close() => _inner.close();
}

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
