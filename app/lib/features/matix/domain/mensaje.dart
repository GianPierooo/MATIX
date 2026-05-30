import 'package:flutter/foundation.dart';

/// Quién emitió un mensaje del chat con Matix.
enum RolMensaje {
  usuario,
  matix;

  /// Serializa al string que espera el cerebro (`user` / `assistant`).
  String toJsonRol() => switch (this) {
        RolMensaje.usuario => 'user',
        RolMensaje.matix => 'assistant',
      };
}

/// Un mensaje en la conversación con Matix.
///
/// Es inmutable: cada turno se agrega como un mensaje nuevo a la
/// lista del notifier — nada se edita in-place. Eso hace que la UI
/// (que `watch`ea la lista) reconstruya solo cuando hay cambios reales.
@immutable
class Mensaje {
  const Mensaje({
    required this.rol,
    required this.contenido,
    required this.enviadoEn,
    this.imagenPath,
  });

  final RolMensaje rol;
  final String contenido;
  final DateTime enviadoEn;

  /// Ruta local de la imagen adjunta (solo para mostrar la miniatura en
  /// la burbuja del usuario). NO se envía al cerebro en `historial` —
  /// la imagen va aparte y solo en el turno actual.
  final String? imagenPath;

  /// Forma que entiende el cerebro en `POST /matix/chat`:
  /// `{"rol": "user"|"assistant", "contenido": "..."}`.
  Map<String, dynamic> toJsonParaCerebro() => {
        'rol': rol.toJsonRol(),
        'contenido': contenido,
      };
}
