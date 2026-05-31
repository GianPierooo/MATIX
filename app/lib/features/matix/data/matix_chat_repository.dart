// Mantenemos `if (x != null) 'k': x` por claridad (mismo patrón que el
// resto de repos). La sintaxis null-aware `?'k': x` hace lo mismo pero
// menos legible en este caso.
// ignore_for_file: use_null_aware_elements

import '../../../api/matix_client.dart';
import '../domain/mensaje.dart';

/// Resultado de un turno de chat con Matix.
///
/// `respuesta` es el texto natural que se le muestra al usuario.
/// `tablasCambiadas` lista las tablas que Matix modificó vía tool
/// calls (p.ej. `["tareas"]` si creó una tarea). La capa de
/// providers la usa para invalidar lo justo y refrescar el hub al
/// instante.
class ChatTurno {
  const ChatTurno({
    required this.respuesta,
    required this.toolsUsadas,
    required this.tablasCambiadas,
    this.navegacion,
  });

  final String respuesta;
  final List<String> toolsUsadas;
  final List<String> tablasCambiadas;

  /// Sección a la que Matix pidió navegar este turno (o `null`). El
  /// string viene del cerebro (`inicio`, `universidad`, `finanzas`…).
  final String? navegacion;

  bool get huboCambios => tablasCambiadas.isNotEmpty;
}

/// Wrapper sobre `MatixClient` para el endpoint `/api/v1/matix/chat`.
///
/// El cerebro espera:
///
///     POST /api/v1/matix/chat
///     {
///       "historial": [{"rol": "user"|"assistant", "contenido": "..."}],
///       "mensaje": "texto del usuario"
///     }
///
/// y devuelve `{"respuesta": "...", "tools_usadas": [...],
/// "tablas_cambiadas": [...]}`. Este repo solo traduce. La lógica
/// de armar el system prompt + contexto vivo + ejecutar tools vive
/// en el cerebro (`cerebro/app/matix/chat.py`).
class MatixChatRepository {
  MatixChatRepository(this._client);
  final MatixClient _client;

  /// Envía `mensaje` con el `historial` previo y devuelve el turno
  /// completo. Lanza `MatixApiException` si el cerebro falla
  /// (503 si falta OPENAI_API_KEY, 502 si OpenAI rechazó, etc.).
  Future<ChatTurno> enviar({
    required List<Mensaje> historial,
    required String mensaje,
    String? imagenDataUrl,
  }) async {
    final body = <String, dynamic>{
      'historial': historial
          .map((m) => m.toJsonParaCerebro())
          .toList(growable: false),
      'mensaje': mensaje,
      // La imagen (data URL) solo viaja en este turno; el cerebro la
      // pasa al modelo de visión y no la guarda en el historial.
      if (imagenDataUrl != null) 'imagen': imagenDataUrl,
    };
    final j = await _client.post('/api/v1/matix/chat', body);
    return ChatTurno(
      respuesta: j['respuesta'] as String,
      toolsUsadas: (j['tools_usadas'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      tablasCambiadas: (j['tablas_cambiadas'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      navegacion: j['navegacion'] as String?,
    );
  }
}
