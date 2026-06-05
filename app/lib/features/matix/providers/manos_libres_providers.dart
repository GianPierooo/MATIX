import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
import '../../wakeword/providers/wakeword_providers.dart';
import '../data/grabacion_voz_service.dart';
import '../data/matix_transcribir_repository.dart';
import '../data/tts_service.dart';
import '../domain/mensaje.dart';
import 'matix_chat_providers.dart';
import 'uso_providers.dart';

/// Fases del bucle manos libres (Capa 2 Paso 5.1).
///
///     iniciando   → arrancando el primer turno (efímero, ~250ms).
///     escuchando  → mic abierto; VAD esperando voz o cortando por
///                   silencio.
///     transcribiendo → audio enviado a /matix/transcribir.
///     pensando    → texto enviado a /matix/chat, esperando respuesta.
///     hablando    → TTS leyendo la respuesta.
///     enPausa     → mic CERRADO, modo activo pero esperando que el
///                   usuario toque "Hablar" para arrancar otra ronda.
///                   Se llega acá por: silencio sin voz al inicio
///                   de la fase escuchando, o por el botón de pausa
///                   manual.
///     error       → algo se rompió; mostrar mensaje y dejar al
///                   usuario decidir si reintenta o sale.
enum FaseManosLibres {
  inactivo,
  iniciando,
  escuchando,
  transcribiendo,
  pensando,
  hablando,
  enPausa,
  error,
}

@immutable
class EstadoManosLibres {
  const EstadoManosLibres({
    this.fase = FaseManosLibres.inactivo,
    this.error,
    this.nivelDb = -60,
    this.notaPausa,
    this.reproduciendo = false,
  });

  final FaseManosLibres fase;
  final String? error;

  /// dBFS instantáneo mientras se escucha — la UI lo usa para una
  /// onda visual.
  final double nivelDb;

  /// Breve nota informativa para mostrar bajo el estado "en pausa".
  /// Distingue "te escuchamos pero no oímos voz" de "tú tocaste
  /// pausa".
  final String? notaPausa;

  /// `true` SOLO mientras el TTS realmente está sonando (no mientras se
  /// descarga). La UI pulsa la onda con esto, así el visual va junto al
  /// audio; al detener/interrumpir se pone en `false` y la onda para con el
  /// sonido.
  final bool reproduciendo;

  EstadoManosLibres copyWith({
    FaseManosLibres? fase,
    Object? error = _kSentinel,
    double? nivelDb,
    Object? notaPausa = _kSentinel,
    bool? reproduciendo,
  }) {
    return EstadoManosLibres(
      fase: fase ?? this.fase,
      error:
          identical(error, _kSentinel) ? this.error : error as String?,
      nivelDb: nivelDb ?? this.nivelDb,
      notaPausa: identical(notaPausa, _kSentinel)
          ? this.notaPausa
          : notaPausa as String?,
      reproduciendo: reproduciendo ?? this.reproduciendo,
    );
  }

  static const _kSentinel = Object();
}

// ── Providers de servicios ──────────────────────────────────────────

/// Servicio TTS del modo manos libres. Público para poder inyectar un fake en
/// los tests (`overrideWithValue`).
final ttsManosLibresProvider = Provider<TtsBase>((ref) {
  final svc = TtsService();
  ref.onDispose(svc.dispose);
  return svc;
});

final _grabServiceProvider = Provider<GrabacionVozService>((ref) {
  final svc = GrabacionVozService();
  ref.onDispose(() => svc.dispose());
  return svc;
});

final _transcribirRepoProvider = Provider<MatixTranscribirRepository>((ref) {
  final repo = MatixTranscribirRepository();
  ref.onDispose(repo.close);
  return repo;
});

final manosLibresProvider =
    NotifierProvider.autoDispose<ManosLibresNotifier, EstadoManosLibres>(
        ManosLibresNotifier.new);

class ManosLibresNotifier extends AutoDisposeNotifier<EstadoManosLibres> {
  bool _saliendo = false;

  /// Cuando el usuario toca "Pausar" o cuando el modo entra en pausa
  /// por silencio, este completer se resuelve para reanudar el loop.
  Completer<void>? _esperaReanudar;

  // Cacheamos los servicios en el primer uso: así el `onDispose` solo limpia
  // lo que de verdad se creó (evita instanciar el mic/TTS sin haberlos usado,
  // que en tests rompería por los plugins nativos).
  TtsBase? _ttsCache;
  TtsBase get _tts {
    _ttsCache ??= ref.read(ttsManosLibresProvider);
    return _ttsCache!;
  }

  GrabacionVozService? _grabCache;
  GrabacionVozService get _grab {
    _grabCache ??= ref.read(_grabServiceProvider);
    return _grabCache!;
  }
  MatixTranscribirRepository get _transcribirRepo =>
      ref.read(_transcribirRepoProvider);

  @override
  EstadoManosLibres build() {
    ref.onDispose(() {
      _saliendo = true;
      // Resolver cualquier espera pendiente para que el loop
      // termine limpio.
      if (_esperaReanudar != null && !_esperaReanudar!.isCompleted) {
        _esperaReanudar!.complete();
      }
      if (_grabCache != null) unawaited(_grabCache!.cancelar());
      if (_ttsCache != null) unawaited(_ttsCache!.detener());
    });
    return const EstadoManosLibres();
  }

  /// Si no nulo, el primer turno se hace sin abrir el mic: el modo
  /// arranca como si el usuario hubiera dicho `_seed` y pasa directo
  /// a pensar → hablar → escuchar. Lo usan los botones de ritual
  /// (Buenos días / Cierre del día) de la pantalla Inicio.
  String? _seed;

  Future<void> entrar({String? seedMensaje}) async {
    if (state.fase != FaseManosLibres.inactivo) return;
    _saliendo = false;
    // FUENTE ÚNICA de verdad del relevo de micro: el modo voz (que usa el
    // micrófono) lo posee este notifier. Lo encendemos al entrar y lo SOLTAMOS
    // en salir() — que la pantalla llama desde deactivate(), una vía que SIEMPRE
    // corre. Antes el reset vivía en el dispose() del widget (ref.read durante
    // dispose es frágil): si no corría, el wake word quedaba pausado para
    // siempre ("en una conversación"). Ahora el dueño del micro garantiza la
    // liberación.
    ref.read(modoVozActivoProvider.notifier).state = true;
    _seed = seedMensaje?.trim().isEmpty ?? true ? null : seedMensaje!.trim();
    state = state.copyWith(
      fase: FaseManosLibres.iniciando,
      error: null,
      notaPausa: null,
    );
    // Dejamos un instante para que la UI pinte el overlay antes de
    // abrir el mic (evita que el "ding" de permiso se solape con
    // la animación de entrada).
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await _bucle();
  }

  /// Entra al modo manos libres por "oye matix": Matix SALUDA por voz y, si hay
  /// una conversación reciente, ofrece retomarla; luego queda escuchando. El
  /// saludo es fijo e instantáneo (no pasa por el modelo), así no hay latencia
  /// ni costo. Si el TTS falla, igual pasa a escuchar (nunca se queda mudo).
  Future<void> entrarPorWakeWord() async {
    if (state.fase != FaseManosLibres.inactivo) return;
    _saliendo = false;
    _seed = null;
    ref.read(modoVozActivoProvider.notifier).state = true;

    final hayConversacion = ref.read(chatMatixProvider).mensajes.isNotEmpty;
    final saludo = saludoWakeWord(hayConversacion: hayConversacion);

    state = state.copyWith(
      fase: FaseManosLibres.iniciando,
      error: null,
      notaPausa: null,
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (_saliendo) return;

    try {
      await _tts.hablar(
        saludo,
        onInicio: () {
          if (_saliendo) return;
          state = state.copyWith(
            fase: FaseManosLibres.hablando,
            reproduciendo: true,
          );
        },
      );
    } catch (_) {
      // El saludo es un plus; si el TTS falla, seguimos a escuchar igual.
    }
    state = state.copyWith(reproduciendo: false);
    if (_saliendo) return;

    await _bucle();
  }

  Future<void> salir() async {
    // SOLTAR el micro para el wake word: lo primero y síncrono (antes de awaits),
    // así el escuchador reanuda al instante. Se ejecuta por TODAS las vías de
    // salida (deactivate de la pantalla, PopScope, botones), garantizando que el
    // wake word nunca quede pegado.
    ref.read(modoVozActivoProvider.notifier).state = false;
    _saliendo = true;
    if (_esperaReanudar != null && !_esperaReanudar!.isCompleted) {
      _esperaReanudar!.complete();
    }
    // Solo tocamos los servicios si llegaron a crearse (mic/TTS son lazy): así
    // un salir() temprano no instancia plugins nativos sin necesidad.
    if (_grabCache != null) await _grabCache!.cancelar();
    if (_ttsCache != null) await _ttsCache!.detener();
    state = const EstadoManosLibres();
  }

  /// Toca el botón "Pausar" estando en `escuchando` o `hablando`.
  Future<void> pausar() async {
    if (state.fase == FaseManosLibres.escuchando) {
      // Cortamos el VAD; el loop verá _saliendo=false pero la
      // próxima vuelta entrará en pausa por la nota.
      await _grab.cancelar();
      _entrarEnPausa('Pausa manual. Toca "Hablar" para seguir.');
    } else if (state.fase == FaseManosLibres.hablando) {
      // Visual y audio paran JUNTOS: la onda se apaga ya y el TTS se corta.
      state = state.copyWith(reproduciendo: false);
      await _tts.detener();
      // Cuando termina el TTS naturalmente o por detener, el loop
      // sigue. Pero como el usuario quiso pausar, marcamos:
      _entrarEnPausa('Pausa manual. Toca "Hablar" para seguir.');
    }
  }

  /// Toca "Hablar" (toca para hablar) estando en pausa.
  void reanudar() {
    if (state.fase != FaseManosLibres.enPausa) return;
    if (_esperaReanudar != null && !_esperaReanudar!.isCompleted) {
      _esperaReanudar!.complete();
    }
  }

  /// Mientras Matix está hablando, esto corta el TTS y la siguiente
  /// vuelta del loop reabre el mic (sin pausa). Visual y audio paran JUNTOS:
  /// apagamos la onda (`reproduciendo=false`) en el mismo momento en que
  /// cortamos el reproductor.
  Future<void> interrumpirHabla() async {
    if (state.fase != FaseManosLibres.hablando) return;
    state = state.copyWith(reproduciendo: false);
    await _tts.detener();
  }

  /// Solo para tests: fija fase/reproduciendo sin correr el bucle.
  @visibleForTesting
  void debugFijarReproduccion(FaseManosLibres fase, {bool reproduciendo = false}) {
    state = state.copyWith(fase: fase, reproduciendo: reproduciendo);
  }

  /// Mientras escucha, corta la escucha AHORA y transcribe lo dicho
  /// hasta este punto (igual que la captura de apuntes). El loop sigue
  /// solo: transcribe → Matix piensa → responde.
  void detenerYTranscribir() {
    if (state.fase != FaseManosLibres.escuchando) return;
    _grab.cortarManual();
  }

  // ── Loop principal ────────────────────────────────────────────────

  void _entrarEnPausa(String nota) {
    state = state.copyWith(
      fase: FaseManosLibres.enPausa,
      notaPausa: nota,
    );
    _esperaReanudar ??= Completer<void>();
  }

  Future<void> _bucle() async {
    while (!_saliendo) {
      try {
        await _turno();
      } on PermisoMicDenegado catch (e) {
        state = state.copyWith(
          fase: FaseManosLibres.error,
          error: e.permanente
              ? 'No tengo permiso de micrófono. Concédelo desde los '
                  'ajustes del sistema y vuelve a entrar al modo.'
              : 'Necesito permiso del micrófono. Acepta el permiso y '
                  'vuelve a entrar.',
        );
        return;
      } on _AbortoUsuario {
        return;
      } catch (e) {
        state = state.copyWith(
          fase: FaseManosLibres.error,
          error: _mensajeDeError(e),
        );
        return;
      }
    }
  }

  Future<void> _turno() async {
    if (_saliendo) throw _AbortoUsuario();

    // Si estamos en pausa, esperar a que el usuario reanude.
    if (state.fase == FaseManosLibres.enPausa) {
      await _esperaReanudar!.future;
      _esperaReanudar = null;
      if (_saliendo) throw _AbortoUsuario();
      // Saliendo de pausa, limpiamos la nota y arrancamos a escuchar.
      state = state.copyWith(notaPausa: null);
    }

    // Primer turno con seed: saltamos escuchar+transcribir y vamos
    // directo a pensar+hablar. Lo usan los rituales de Inicio.
    if (_seed != null) {
      final texto = _seed!;
      _seed = null;
      await _turnoConTexto(texto);
      return;
    }

    // 1) ESCUCHAR con VAD
    state = state.copyWith(
      fase: FaseManosLibres.escuchando,
      nivelDb: -60,
    );
    final esc = await _grab.escucharConVad(
      onAmplitud: (db) {
        if (_saliendo) return;
        if (state.fase == FaseManosLibres.escuchando) {
          state = state.copyWith(nivelDb: db);
        }
      },
    );
    if (_saliendo) throw _AbortoUsuario();

    switch (esc.resultado) {
      case ResultadoEscucha.sinVoz:
        _entrarEnPausa(
          'No escuché nada. Toca "Hablar" cuando quieras retomar.',
        );
        return;
      case ResultadoEscucha.cancelada:
        // Cancelación externa (pausar() la llamó); ya estará en
        // pausa para el próximo loop.
        return;
      case ResultadoEscucha.cortada:
      case ResultadoEscucha.topeAlcanzado:
        break;
    }

    final grab = esc.grabacion;
    if (grab == null) return;
    if (grab.duracion < const Duration(milliseconds: 600)) {
      try {
        await grab.archivo.delete();
      } catch (_) {}
      return;
    }

    // 2) TRANSCRIBIR
    state = state.copyWith(fase: FaseManosLibres.transcribiendo);
    String texto;
    try {
      texto = await _transcribirRepo.transcribir(grab.archivo);
    } finally {
      try {
        await grab.archivo.delete();
      } catch (_) {}
    }
    if (_saliendo) throw _AbortoUsuario();

    // El cerebro descarta alucinaciones de Whisper y devuelve "".
    // Si llega vacío, volvemos a escuchar.
    if (texto.trim().isEmpty) return;

    // 3+4) PENSAR + HABLAR
    await _turnoConTexto(texto);
  }

  /// Manda `texto` al chat como si fuera input del usuario, y lee
  /// la respuesta con TTS. Se usa tanto cuando el texto vino de
  /// Whisper (flujo normal) como cuando vino como seed de un botón
  /// de ritual.
  Future<void> _turnoConTexto(String texto) async {
    // 3) PENSAR — usamos chatMatixProvider, que comparte historial
    // con el chat normal.
    state = state.copyWith(fase: FaseManosLibres.pensando);
    await ref.read(chatMatixProvider.notifier).enviar(texto);
    if (_saliendo) throw _AbortoUsuario();

    final estadoChat = ref.read(chatMatixProvider);
    if (estadoChat.errorUltimoEnvio != null) {
      throw StateError(estadoChat.errorUltimoEnvio!);
    }
    final ultima = estadoChat.mensajes.lastWhere(
      (m) => m.rol == RolMensaje.matix,
      orElse: () => Mensaje(
        rol: RolMensaje.matix,
        contenido: '',
        enviadoEn: DateTime.now(),
      ),
    );
    // Forzamos refresco del medidor — la franja del chat necesita
    // verlo, y como Matix también puede ejecutar tools dentro de
    // manos libres, también podría haber cambios visuales en el hub.
    ref.invalidate(usoSnapshotProvider);

    final respuesta = ultima.contenido;
    if (respuesta.isEmpty) return;

    // 4) HABLAR. La fase sigue en "pensando" mientras se DESCARGA el audio;
    // pasa a "hablando" (con la onda) recién cuando SUENA de verdad (onInicio),
    // así el visual va junto al audio y no antes. Al terminar (o al cortar con
    // detener), `reproduciendo` vuelve a false y la onda para con el sonido.
    // La voz va en su propio intento: si el TTS falla (502/timeout, ya con
    // reintentos), NO tumbamos el modo manos libres — el texto ya se mostró en
    // el chat. Degradamos: saltamos el audio y seguimos escuchando.
    try {
      await _tts.hablar(
        respuesta,
        onInicio: () {
          if (_saliendo) return;
          state = state.copyWith(
            fase: FaseManosLibres.hablando,
            reproduciendo: true,
          );
        },
      );
    } catch (_) {
      // Sin voz este turno; el texto quedó. Seguimos el bucle.
    }
    state = state.copyWith(reproduciendo: false);
    if (_saliendo) throw _AbortoUsuario();

    // Pequeña pausa antes del próximo mic.
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}

class _AbortoUsuario implements Exception {}

/// Texto del saludo cuando se abre por "oye matix". Si hay una conversación
/// reciente, ofrece retomarla; si no, saluda y queda escuchando. Español "tú",
/// sin asteriscos. Función pura para poder testearla.
String saludoWakeWord({required bool hayConversacion}) {
  return hayConversacion
      ? '¡Hola, Piero! ¿Seguimos con lo que estábamos?'
      : '¡Hola, Piero!';
}

String _mensajeDeError(Object e) {
  if (e is MatixApiException) {
    if (e.statusCode == 503) {
      return 'La voz no está disponible ahora mismo. (${e.message})';
    }
    if (e.statusCode == 413) {
      return 'Hablaste muy largo. Intenta decirlo en fragmentos más cortos.';
    }
    if (e.statusCode == 0) {
      return 'No pude llegar al cerebro. ¿Está corriendo?';
    }
    return 'Falló la voz (${e.statusCode}): ${e.message}';
  }
  if (e is StateError) return e.message;
  return 'Algo se rompió en el modo manos libres: $e';
}
