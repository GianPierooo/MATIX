import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Puente con el lado nativo (MainActivity.kt) para recibir lo que el
/// usuario comparte a Matix desde otras apps con el menú "compartir"
/// de Android (texto plano y URLs — Capa 7).
///
/// Dos vías, según si la app estaba abierta cuando se compartió:
///
/// - [obtenerTextoInicial]: el texto del intent que ARRANCÓ la app
///   (se compartió con Matix cerrado). El nativo lo entrega una sola
///   vez; devolvemos null si no hay nada o si ya se consumió.
/// - [escuchar]: registra un callback que dispara cuando llega un
///   compartido con la app YA abierta (onNewIntent en el nativo).
///
/// Devuelve siempre texto trimmeado y no vacío, o null.
class ShareIntentService {
  ShareIntentService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('dev.matix.matix/share');

  final MethodChannel _channel;

  /// Texto compartido que arrancó la app, o null si no hubo (apertura
  /// normal) o ya se consumió.
  ///
  /// Si el canal nativo no responde (entorno sin la plataforma, o un
  /// fallo del plugin), devolvemos null en vez de romper el arranque:
  /// no recibir un compartido nunca debe tumbar la app.
  Future<String?> obtenerTextoInicial() async {
    try {
      final texto =
          await _channel.invokeMethod<String>('getInitialSharedText');
      return _limpio(texto);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Llama [onTexto] cada vez que llega un compartido con la app
  /// abierta. Ignora textos vacíos.
  void escuchar(void Function(String texto) onTexto) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedText') {
        final texto = _limpio(call.arguments as String?);
        if (texto != null) onTexto(texto);
      }
      return null;
    });
  }

  String? _limpio(String? crudo) {
    final t = crudo?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}

final shareIntentServiceProvider =
    Provider<ShareIntentService>((ref) => ShareIntentService());
