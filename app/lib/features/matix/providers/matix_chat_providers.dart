import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../../core/providers.dart';
import '../../apuntes/providers/apuntes_providers.dart';
import '../../cierre/providers/cierres_providers.dart';
import '../../eventos/providers/eventos_providers.dart';
import '../../finanzas/providers/movimientos_providers.dart';
import '../../memoria/data/memoria_repository.dart';
import '../../modos/providers/modos_providers.dart';
import '../../proyectos/providers/proyectos_providers.dart';
import '../../tareas/providers/tareas_providers.dart';
import '../data/matix_chat_repository.dart';
import '../domain/mensaje.dart';
import 'navegacion_matix_provider.dart';
import 'uso_providers.dart';

final matixChatRepositoryProvider = Provider<MatixChatRepository>((ref) {
  return MatixChatRepository(ref.watch(matixClientProvider));
});

/// Estado de la conversación con Matix.
///
/// - `mensajes` es el historial completo en orden cronológico.
/// - `enviando` indica si hay un POST en vuelo (para deshabilitar el
///   input y mostrar el "Matix está pensando").
/// - `errorUltimoEnvio` es no-nulo cuando el último intento falló; la
///   UI lo muestra como tarjeta inline con un botón "Reintentar". Se
///   limpia al mandar otro mensaje o al abrir/limpiar el chat.
/// - `accionesUltimoTurno` lista los nombres de las herramientas
///   que Matix usó en el último turno (`crear_tarea`, etc.). La UI
///   lo aprovecha para mostrar un chip discreto bajo la burbuja del
///   asistente que confirma visualmente la acción.
@immutable
class EstadoChatMatix {
  const EstadoChatMatix({
    this.mensajes = const <Mensaje>[],
    this.enviando = false,
    this.errorUltimoEnvio,
    this.accionesUltimoTurno = const <String>[],
  });

  final List<Mensaje> mensajes;
  final bool enviando;
  final String? errorUltimoEnvio;
  final List<String> accionesUltimoTurno;

  EstadoChatMatix copyWith({
    List<Mensaje>? mensajes,
    bool? enviando,
    Object? errorUltimoEnvio = _kSentinel,
    List<String>? accionesUltimoTurno,
  }) {
    return EstadoChatMatix(
      mensajes: mensajes ?? this.mensajes,
      enviando: enviando ?? this.enviando,
      errorUltimoEnvio: identical(errorUltimoEnvio, _kSentinel)
          ? this.errorUltimoEnvio
          : errorUltimoEnvio as String?,
      accionesUltimoTurno: accionesUltimoTurno ?? this.accionesUltimoTurno,
    );
  }

  static const _kSentinel = Object();
}

final chatMatixProvider =
    NotifierProvider<ChatMatixNotifier, EstadoChatMatix>(
        ChatMatixNotifier.new);

/// Notifier de la conversación.
///
/// El historial vive aquí, en memoria. Si el usuario cierra la app y
/// vuelve, arranca en blanco — eso es lo correcto para Capa 2 Paso 1:
/// la persistencia del hilo es Paso 7 (memoria conversacional).
class ChatMatixNotifier extends Notifier<EstadoChatMatix> {
  @override
  EstadoChatMatix build() => const EstadoChatMatix();

  /// Borra todo el historial y cualquier error.
  void limpiar() {
    state = const EstadoChatMatix();
  }

  /// Envía `texto` al cerebro, agrega el mensaje del usuario al
  /// historial *antes* del POST (para que se vea en la lista mientras
  /// Matix piensa), y al terminar agrega la respuesta o registra el
  /// error.
  ///
  /// Si Matix usó herramientas para cambiar el hub (`crear_tarea`,
  /// etc.), invalidamos los providers de las tablas afectadas para
  /// que la UI refleje el cambio sin que el usuario tenga que
  /// recargar la pestaña.
  Future<void> enviar(
    String texto, {
    String? imagenDataUrl,
    String? imagenPath,
  }) async {
    final t = texto.trim();
    // Permitimos mandar solo imagen (sin texto). Si no hay ni texto ni
    // imagen, no hay nada que enviar.
    if ((t.isEmpty && imagenDataUrl == null) || state.enviando) return;

    // Cuando solo se adjunta imagen, mandamos un texto por defecto: el
    // schema del cerebro exige `mensaje` no vacío y le da una
    // instrucción al modelo.
    final mensaje =
        t.isEmpty ? 'Mira esta imagen y ayúdame con lo que muestre.' : t;

    // Historial que se manda al cerebro: el de ANTES de agregar el
    // nuevo mensaje (el endpoint espera `historial` separado del
    // `mensaje` actual).
    final historialPrevio = state.mensajes;

    final propio = Mensaje(
      rol: RolMensaje.usuario,
      contenido: t,
      enviadoEn: DateTime.now(),
      imagenPath: imagenPath,
    );
    state = state.copyWith(
      mensajes: [...historialPrevio, propio],
      enviando: true,
      errorUltimoEnvio: null,
      accionesUltimoTurno: const <String>[],
    );

    try {
      final repo = ref.read(matixChatRepositoryProvider);
      final turno = await repo.enviar(
        historial: historialPrevio,
        mensaje: mensaje,
        imagenDataUrl: imagenDataUrl,
      );
      final ans = Mensaje(
        rol: RolMensaje.matix,
        contenido: turno.respuesta,
        enviadoEn: DateTime.now(),
      );
      state = state.copyWith(
        mensajes: [...state.mensajes, ans],
        enviando: false,
        accionesUltimoTurno: turno.toolsUsadas,
      );
      // Refrescar el hub si Matix tocó algo
      _invalidarProviders(turno.tablasCambiadas);
      // Si pidió navegar, dejamos el objetivo para que el HomeShell abra
      // la sección. One-shot: el shell lo consume y lo vuelve a null.
      final destino = seccionMatixDeString(turno.navegacion);
      if (destino != null) {
        ref.read(objetivoNavegacionProvider.notifier).state = destino;
      }
      // Sincroniza el indicador de modo: el modelo pudo activar/desactivar
      // un modo con una tool este turno. Refleja el estado post-turno.
      ref.read(modosProvider.notifier).sincronizar(turno.modoActivo);
      // El medidor cambió: hubo al menos una llamada al modelo.
      ref.invalidate(usoSnapshotProvider);
    } catch (e) {
      // El mensaje del usuario se queda en el historial; el error se
      // muestra inline con botón "Reintentar". Reintentar reusará el
      // último mensaje del usuario.
      state = state.copyWith(
        enviando: false,
        errorUltimoEnvio: _mensajeDeError(e),
      );
    }
  }

  /// Para cada tabla que Matix tocó, invalida el provider raíz que
  /// la representa. Los providers derivados (filtrados, por id,
  /// agrupados, etc.) se recalculan automáticamente porque hacen
  /// `watch` del raíz.
  ///
  /// El mapeo nombre-tabla → provider es chico y vive acá. Si en el
  /// futuro Matix toca otra tabla, agregar un caso nuevo.
  void _invalidarProviders(List<String> tablas) {
    for (final tabla in tablas) {
      switch (tabla) {
        case 'tareas':
          ref.invalidate(tareasProvider);
        case 'eventos':
          ref.invalidate(eventosProvider);
        case 'apuntes':
          ref.invalidate(apuntesListProvider);
        case 'proyectos':
          ref.invalidate(proyectosListProvider);
        case 'movimientos':
          ref.invalidate(movimientosListProvider);
        case 'memoria':
          ref.invalidate(memoriaListProvider);
        case 'cierres_dia':
          ref.invalidate(cierresListProvider);
        // Tabla desconocida → ignoramos en silencio; nuevas tablas
        // se agregan al cerebro y a este switch en el mismo paso.
      }
    }
  }

  /// Reenvía el último mensaje del usuario sin duplicarlo en la lista.
  /// Útil después de un error de red / 502 / 503.
  Future<void> reintentar() async {
    if (state.enviando) return;
    final ultimo = state.mensajes.lastOrNull;
    if (ultimo == null || ultimo.rol != RolMensaje.usuario) return;

    // Quitamos el último mensaje del usuario (lo va a volver a poner
    // `enviar`) y reenviamos.
    final historialPrevio =
        state.mensajes.sublist(0, state.mensajes.length - 1);
    state = state.copyWith(
      mensajes: historialPrevio,
      errorUltimoEnvio: null,
    );
    await enviar(ultimo.contenido);
  }
}

String _mensajeDeError(Object e) {
  if (e is MatixApiException) {
    if (e.statusCode == 503) {
      return 'Matix no está disponible ahora mismo. '
          '(${e.message})';
    }
    if (e.statusCode == 0) {
      return 'No pude llegar al cerebro. Verifica que esté corriendo. '
          '(${e.message})';
    }
    return 'Error del cerebro (${e.statusCode}): ${e.message}';
  }
  return 'Error inesperado: $e';
}
