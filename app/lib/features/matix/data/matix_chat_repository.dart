// Mantenemos `if (x != null) 'k': x` por claridad (mismo patrón que el
// resto de repos). La sintaxis null-aware `?'k': x` hace lo mismo pero
// menos legible en este caso.
// ignore_for_file: use_null_aware_elements

import '../../../api/matix_client.dart';
import '../domain/mensaje.dart';
import 'accion_dispositivo.dart';

/// Resultado de un turno de chat con Matix.
///
/// `respuesta` es el texto natural que se le muestra al usuario.
/// `tablasCambiadas` lista las tablas que Matix modificó vía tool
/// calls (p.ej. `["tareas"]` si creó una tarea). La capa de
/// providers la usa para invalidar lo justo y refrescar el hub al
/// instante.
/// Bloque interactivo de opciones tocables (estilo Claude). Matix lo emite
/// con `preguntar_con_opciones`; la app lo pinta debajo del mensaje.
class BloqueOpciones {
  const BloqueOpciones({
    required this.pregunta,
    required this.opciones,
    required this.tipo,
  });

  final String pregunta;
  final List<String> opciones;

  /// 'seleccion_unica' | 'seleccion_multiple' | 'texto'.
  final String tipo;

  bool get esTexto => tipo == 'texto';
  bool get esMultiple => tipo == 'seleccion_multiple';

  factory BloqueOpciones.fromJson(Map<String, dynamic> j) => BloqueOpciones(
        pregunta: (j['pregunta'] as String?) ?? '',
        opciones: (j['opciones'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(growable: false),
        tipo: (j['tipo'] as String?) ?? 'seleccion_unica',
      );
}

class ChatTurno {
  const ChatTurno({
    required this.respuesta,
    required this.toolsUsadas,
    required this.tablasCambiadas,
    this.navegacion,
    this.accionDispositivo,
    this.modoActivo,
    this.opciones,
    this.modeloUsado,
    this.auto = false,
  });

  final String respuesta;
  final List<String> toolsUsadas;
  final List<String> tablasCambiadas;

  /// Sección a la que Matix pidió navegar este turno (o `null`). El
  /// string viene del cerebro (`inicio`, `universidad`, `finanzas`…).
  final String? navegacion;

  /// Acción de teléfono que Matix propuso este turno (Capa 6 · Fase 1), o
  /// `null`. La app la confirma (si hace falta) y lanza el Intent nativo.
  final AccionDispositivo? accionDispositivo;

  /// Modo de Matix activo DESPUÉS del turno (el modelo pudo cambiarlo con
  /// `activar_modo`/`desactivar_modo`). `null` = modo normal.
  final String? modoActivo;

  /// Bloque interactivo de opciones tocables, o `null`. Si viene, la app lo
  /// pinta debajo del mensaje y tocar una opción la manda como respuesta.
  final BloqueOpciones? opciones;

  /// Id del modelo que respondió este turno (transparencia). `null` si el
  /// cerebro no lo reportó (versión vieja).
  final String? modeloUsado;

  /// `true` si el modelo lo eligió el modo Automático. La app muestra la
  /// etiqueta del modelo usado sobre todo en este caso.
  final bool auto;

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
    List<String> imagenes = const [],
    String? documentoNombre,
    String? documentoTexto,
    String? idempotencyKey,
  }) async {
    final body = <String, dynamic>{
      'historial': historial
          .map((m) => m.toJsonParaCerebro())
          .toList(growable: false),
      'mensaje': mensaje,
      // Clave de idempotencia: si reintentamos tras una caída con la MISMA
      // clave, el cerebro devuelve el resultado guardado sin duplicar nada.
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      // Las imágenes (data URL) solo viajan en este turno; el cerebro las
      // pasa al modelo de visión y no las guarda en el historial. Se pueden
      // mandar varias por mensaje.
      if (imagenes.isNotEmpty) 'imagenes': imagenes,
      // El documento adjunto (texto ya extraído por el cerebro) también es
      // contexto solo de este turno.
      if (documentoTexto != null && documentoTexto.isNotEmpty)
        'documento': {
          'nombre': documentoNombre ?? 'documento',
          'texto': documentoTexto,
        },
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
      accionDispositivo: AccionDispositivo.fromJson(j['accion_dispositivo']),
      modoActivo: j['modo_activo'] as String?,
      opciones: j['opciones'] is Map<String, dynamic>
          ? BloqueOpciones.fromJson(j['opciones'] as Map<String, dynamic>)
          : null,
      modeloUsado: j['modelo_usado'] as String?,
      auto: (j['auto'] as bool?) ?? false,
    );
  }
}
