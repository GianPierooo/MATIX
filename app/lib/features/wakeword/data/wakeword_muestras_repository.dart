import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../api/matix_client.dart';
import '../../../config.dart';

/// Conteo de muestras guardadas en el servidor (positivos / negativos).
class ConteoMuestras {
  const ConteoMuestras({this.positivo = 0, this.negativo = 0, this.total = 0});

  final int positivo;
  final int negativo;
  final int total;

  factory ConteoMuestras.fromJson(Map<String, dynamic> j) => ConteoMuestras(
        positivo: (j['positivo'] as num?)?.toInt() ?? 0,
        negativo: (j['negativo'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
      );
}

/// Sube las grabaciones de voz para entrenar el wake word "oye matix" a la voz
/// real del usuario.
///
/// Habla con el cerebro (`/matix/wakeword/muestras`), que guarda los clips en
/// un bucket PRIVADO de Supabase Storage con la `service_role` del servidor —
/// la app nunca toca esa clave. Como `/matix/transcribir`, usa multipart
/// directo con `http` (no los helpers JSON) e inyecta `X-Matix-Key`.
class WakeWordMuestrasRepository {
  WakeWordMuestrasRepository({http.Client? inner})
      : _inner = inner ?? http.Client();

  final http.Client _inner;

  String get _base => '${MatixConfig.apiUrl}/api/v1/matix/wakeword/muestras';

  void _auth(http.BaseRequest req) {
    if (MatixConfig.hasApiKey) {
      req.headers['X-Matix-Key'] = MatixConfig.apiKey;
    }
  }

  /// Sube un clip (`tipo` = `positivo` | `negativo`, `indice` dentro de su
  /// tipo). Devuelve el conteo actualizado. Lanza [MatixApiException] si el
  /// cerebro responde error.
  Future<ConteoMuestras> subir({
    required File wav,
    required String tipo,
    required int indice,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse(_base));
    _auth(req);
    req.fields['tipo'] = tipo;
    req.fields['indice'] = '$indice';
    req.files.add(
      await http.MultipartFile.fromPath(
        'file',
        wav.path,
        filename: '$tipo-$indice.wav',
      ),
    );
    final streamed = await _inner.send(req).timeout(const Duration(seconds: 30));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) {
      throw MatixApiException(resp.statusCode, _msg(resp.body));
    }
    final body = json.decode(resp.body) as Map<String, dynamic>;
    return ConteoMuestras.fromJson(
      (body['conteo'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  /// Cuántas muestras hay guardadas en el servidor.
  Future<ConteoMuestras> conteo() async {
    final req = http.Request('GET', Uri.parse('$_base/conteo'));
    _auth(req);
    final streamed = await _inner.send(req).timeout(const Duration(seconds: 20));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) {
      throw MatixApiException(resp.statusCode, _msg(resp.body));
    }
    return ConteoMuestras.fromJson(
      json.decode(resp.body) as Map<String, dynamic>,
    );
  }

  /// Borra todas las muestras del servidor (empezar de cero).
  Future<ConteoMuestras> borrarTodo() async {
    final req = http.Request('DELETE', Uri.parse(_base));
    _auth(req);
    final streamed = await _inner.send(req).timeout(const Duration(seconds: 30));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) {
      throw MatixApiException(resp.statusCode, _msg(resp.body));
    }
    return ConteoMuestras.fromJson(
      json.decode(resp.body) as Map<String, dynamic>,
    );
  }

  void close() => _inner.close();

  String _msg(String body) {
    if (body.isEmpty) return '(sin detalle)';
    try {
      final j = json.decode(body);
      if (j is Map && j['detail'] != null) {
        final d = j['detail'];
        if (d is String) return d;
      }
    } catch (_) {
      // body no es JSON
    }
    return body.length > 200 ? '${body.substring(0, 200)}…' : body;
  }
}
