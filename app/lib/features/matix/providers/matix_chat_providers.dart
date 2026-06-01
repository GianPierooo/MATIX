import 'dart:async';
import 'dart:math';

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
    this.opcionesUltimoTurno,
    this.modeloUltimoTurno,
    this.autoUltimoTurno = false,
    this.reconectando = false,
  });

  final List<Mensaje> mensajes;
  final bool enviando;
  final String? errorUltimoEnvio;
  final List<String> accionesUltimoTurno;

  /// `true` cuando un envío se cayó por una caída transitoria (saliste de la
  /// app un momento) y estamos reintentando solos con la misma clave. NO es un
  /// error rojo: la UI muestra un "Reconectando…" suave.
  final bool reconectando;

  /// Bloque interactivo de opciones del último turno del asistente (o `null`).
  /// La UI lo pinta bajo la burbuja; tocar una opción la manda como respuesta.
  final BloqueOpciones? opcionesUltimoTurno;

  /// Id del modelo que respondió el último turno (transparencia). `null`
  /// si aún no hubo respuesta o el cerebro no lo reportó.
  final String? modeloUltimoTurno;

  /// `true` si ese modelo lo eligió el modo Automático.
  final bool autoUltimoTurno;

  EstadoChatMatix copyWith({
    List<Mensaje>? mensajes,
    bool? enviando,
    Object? errorUltimoEnvio = _kSentinel,
    List<String>? accionesUltimoTurno,
    Object? opcionesUltimoTurno = _kSentinel,
    Object? modeloUltimoTurno = _kSentinel,
    bool? autoUltimoTurno,
    bool? reconectando,
  }) {
    return EstadoChatMatix(
      mensajes: mensajes ?? this.mensajes,
      enviando: enviando ?? this.enviando,
      errorUltimoEnvio: identical(errorUltimoEnvio, _kSentinel)
          ? this.errorUltimoEnvio
          : errorUltimoEnvio as String?,
      accionesUltimoTurno: accionesUltimoTurno ?? this.accionesUltimoTurno,
      opcionesUltimoTurno: identical(opcionesUltimoTurno, _kSentinel)
          ? this.opcionesUltimoTurno
          : opcionesUltimoTurno as BloqueOpciones?,
      modeloUltimoTurno: identical(modeloUltimoTurno, _kSentinel)
          ? this.modeloUltimoTurno
          : modeloUltimoTurno as String?,
      autoUltimoTurno: autoUltimoTurno ?? this.autoUltimoTurno,
      reconectando: reconectando ?? this.reconectando,
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
    List<String> imagenesDataUrl = const [],
    List<String> imagenPaths = const [],
    String? documentoNombre,
    String? documentoTexto,
  }) async {
    final t = texto.trim();
    final hayDocumento = documentoTexto != null && documentoTexto.isNotEmpty;
    final hayImagenes = imagenesDataUrl.isNotEmpty;
    // Permitimos mandar solo imágenes o solo documento (sin texto). Si no hay
    // nada de eso, no hay nada que enviar.
    if ((t.isEmpty && !hayImagenes && !hayDocumento) || state.enviando) {
      return;
    }

    // Cuando solo se adjunta imagen o documento (sin texto), mandamos un
    // texto por defecto: el schema del cerebro exige `mensaje` no vacío y le
    // da una instrucción al modelo.
    final String mensaje;
    if (t.isNotEmpty) {
      mensaje = t;
    } else if (hayDocumento) {
      mensaje = 'Lee este documento y dime de qué trata.';
    } else if (imagenesDataUrl.length > 1) {
      mensaje = 'Mira estas imágenes y ayúdame con lo que muestren.';
    } else {
      mensaje = 'Mira esta imagen y ayúdame con lo que muestre.';
    }

    // Historial que se manda al cerebro: el de ANTES de agregar el
    // nuevo mensaje (el endpoint espera `historial` separado del
    // `mensaje` actual).
    final historialPrevio = state.mensajes;

    final propio = Mensaje(
      rol: RolMensaje.usuario,
      contenido: t,
      enviadoEn: DateTime.now(),
      imagenPaths: imagenPaths,
    );
    state = state.copyWith(
      mensajes: [...historialPrevio, propio],
      enviando: true,
      errorUltimoEnvio: null,
      reconectando: false,
      accionesUltimoTurno: const <String>[],
      // Al mandar un mensaje nuevo, el bloque de opciones anterior ya no aplica.
      opcionesUltimoTurno: null,
    );

    // Guardamos lo necesario para REINTENTAR con la MISMA clave de
    // idempotencia si la conexión se cae (saliste un momento). Reintentar con
    // la misma clave no duplica nada y recupera el resultado.
    _pendiente = _PendienteEnvio(
      mensaje: mensaje,
      imagenes: imagenesDataUrl,
      historialPrevio: historialPrevio,
      documentoNombre: documentoNombre,
      documentoTexto: documentoTexto,
      idemKey: _nuevaIdemKey(),
    );
    _intentos = 0;
    await _despacharPendiente();
  }

  // ── Envío con reintento idempotente + reconexión suave ────────────

  _PendienteEnvio? _pendiente;
  int _intentos = 0;
  static const int _maxIntentos = 4;

  bool _esTransitorio(Object e) =>
      e is MatixApiException &&
      // 0 = sin respuesta/conexión abortada (saliste de la app); 409 = el
      // cerebro sigue procesando ese turno; 408 = timeout.
      (e.statusCode == 0 || e.statusCode == 409 || e.statusCode == 408);

  /// Manda (o reintenta) el turno pendiente. En éxito aplica el resultado; en
  /// caída transitoria deja "reconectando" y reintenta solo; en error duro
  /// muestra el error rojo.
  Future<void> _despacharPendiente() async {
    final p = _pendiente;
    if (p == null) return;
    state = state.copyWith(enviando: true, reconectando: false);
    try {
      final repo = ref.read(matixChatRepositoryProvider);
      final turno = await repo.enviar(
        historial: p.historialPrevio,
        mensaje: p.mensaje,
        imagenes: p.imagenes,
        documentoNombre: p.documentoNombre,
        documentoTexto: p.documentoTexto,
        idempotencyKey: p.idemKey,
      );
      _pendiente = null;
      _intentos = 0;
      final ans = Mensaje(
        rol: RolMensaje.matix,
        contenido: turno.respuesta,
        enviadoEn: DateTime.now(),
      );
      state = state.copyWith(
        mensajes: [...state.mensajes, ans],
        enviando: false,
        reconectando: false,
        accionesUltimoTurno: turno.toolsUsadas,
        opcionesUltimoTurno: turno.opciones,
        modeloUltimoTurno: turno.modeloUsado,
        autoUltimoTurno: turno.auto,
      );
      _invalidarProviders(turno.tablasCambiadas);
      final destino = seccionMatixDeString(turno.navegacion);
      if (destino != null) {
        ref.read(objetivoNavegacionProvider.notifier).state = destino;
      }
      ref.read(modosProvider.notifier).sincronizar(turno.modoActivo);
      ref.invalidate(usoSnapshotProvider);
    } catch (e) {
      if (_esTransitorio(e)) {
        // Caída transitoria: NADA de error rojo. Reconectando + reintento
        // solo (mismo idemKey → sin duplicar). El mensaje del usuario queda.
        _intentos++;
        state = state.copyWith(enviando: false, reconectando: true);
        if (_intentos < _maxIntentos) {
          final espera = Duration(seconds: (_intentos * 2).clamp(2, 8));
          Future<void>.delayed(espera, () {
            if (_pendiente != null && !state.enviando) {
              unawaited(_despacharPendiente());
            }
          });
        }
        // Si se agotan los intentos, queda `reconectando` con el botón manual.
      } else {
        // Error duro (503/502/400…): rojo, y descartamos el pendiente.
        _pendiente = null;
        state = state.copyWith(
          enviando: false,
          reconectando: false,
          errorUltimoEnvio: _mensajeDeError(e),
        );
      }
    }
  }

  /// Reintenta YA el turno pendiente (lo llama el ciclo de vida al volver a la
  /// app, y el botón "Reintentar" del aviso de reconexión).
  void reconectarAhora() {
    if (_pendiente != null && !state.enviando) {
      _intentos = 0;
      unawaited(_despacharPendiente());
    }
  }

  String _nuevaIdemKey() {
    final r = Random();
    final a = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final b = r.nextInt(1 << 32).toRadixString(16);
    final c = r.nextInt(1 << 32).toRadixString(16);
    return 'mk_${a}_${b}_$c';
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

  /// Botón "Reintentar". Si hay un turno pendiente (caída transitoria),
  /// reintenta con la MISMA clave (no duplica). Si fue un error duro, reenvía
  /// el último mensaje del usuario sin duplicarlo en la lista.
  Future<void> reintentar() async {
    if (state.enviando) return;
    if (_pendiente != null) {
      reconectarAhora();
      return;
    }
    final ultimo = state.mensajes.lastOrNull;
    if (ultimo == null || ultimo.rol != RolMensaje.usuario) return;
    final historialPrevio =
        state.mensajes.sublist(0, state.mensajes.length - 1);
    state = state.copyWith(
      mensajes: historialPrevio,
      errorUltimoEnvio: null,
    );
    await enviar(ultimo.contenido);
  }
}

/// Lo que se necesita para REINTENTAR un turno con su misma clave de
/// idempotencia tras una caída transitoria.
class _PendienteEnvio {
  _PendienteEnvio({
    required this.mensaje,
    required this.imagenes,
    required this.historialPrevio,
    required this.idemKey,
    this.documentoNombre,
    this.documentoTexto,
  });

  final String mensaje;
  final List<String> imagenes;
  final List<Mensaje> historialPrevio;
  final String idemKey;
  final String? documentoNombre;
  final String? documentoTexto;
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
