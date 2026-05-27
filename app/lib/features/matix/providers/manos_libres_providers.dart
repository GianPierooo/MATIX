import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/matix_client.dart';
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
  });

  final FaseManosLibres fase;
  final String? error;

  /// dBFS instantáneo mientras se escucha — la UI lo usa para una
  /// onda visual.
  final double nivelDb;

  /// Breve nota informativa para mostrar bajo el estado "en pausa".
  /// Distingue "te escuchamos pero no oímos voz" de "vos tocaste
  /// pausa".
  final String? notaPausa;

  EstadoManosLibres copyWith({
    FaseManosLibres? fase,
    Object? error = _kSentinel,
    double? nivelDb,
    Object? notaPausa = _kSentinel,
  }) {
    return EstadoManosLibres(
      fase: fase ?? this.fase,
      error:
          identical(error, _kSentinel) ? this.error : error as String?,
      nivelDb: nivelDb ?? this.nivelDb,
      notaPausa: identical(notaPausa, _kSentinel)
          ? this.notaPausa
          : notaPausa as String?,
    );
  }

  static const _kSentinel = Object();
}

// ── Providers de servicios ──────────────────────────────────────────

final _ttsServiceProvider = Provider<TtsService>((ref) {
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

  TtsService get _tts => ref.read(_ttsServiceProvider);
  GrabacionVozService get _grab => ref.read(_grabServiceProvider);
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
      unawaited(_grab.cancelar());
      unawaited(_tts.detener());
    });
    return const EstadoManosLibres();
  }

  Future<void> entrar() async {
    if (state.fase != FaseManosLibres.inactivo) return;
    _saliendo = false;
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

  Future<void> salir() async {
    _saliendo = true;
    if (_esperaReanudar != null && !_esperaReanudar!.isCompleted) {
      _esperaReanudar!.complete();
    }
    await _grab.cancelar();
    await _tts.detener();
    state = const EstadoManosLibres();
  }

  /// Toca el botón "Pausar" estando en `escuchando` o `hablando`.
  Future<void> pausar() async {
    if (state.fase == FaseManosLibres.escuchando) {
      // Cortamos el VAD; el loop verá _saliendo=false pero la
      // próxima vuelta entrará en pausa por la nota.
      await _grab.cancelar();
      _entrarEnPausa('Pausa manual. Tocá "Hablar" para seguir.');
    } else if (state.fase == FaseManosLibres.hablando) {
      await _tts.detener();
      // Cuando termina el TTS naturalmente o por detener, el loop
      // sigue. Pero como el usuario quiso pausar, marcamos:
      _entrarEnPausa('Pausa manual. Tocá "Hablar" para seguir.');
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
  /// vuelta del loop reabre el mic (sin pausa).
  Future<void> interrumpirHabla() async {
    if (state.fase != FaseManosLibres.hablando) return;
    await _tts.detener();
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
              ? 'No tengo permiso de micrófono. Concedelo desde los '
                  'ajustes del sistema y volvé a entrar al modo.'
              : 'Necesito permiso del micrófono. Aceptá el permiso y '
                  'volvé a entrar.',
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
          'No escuché nada. Tocá "Hablar" cuando quieras retomar.',
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

    // 3) PENSAR — usamos el chatMatixProvider, que comparte
    // historial con el chat normal.
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

    // 4) HABLAR
    state = state.copyWith(
      fase: FaseManosLibres.hablando,
    );
    await _tts.hablar(respuesta);
    if (_saliendo) throw _AbortoUsuario();

    // Pequeña pausa antes del próximo mic.
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}

class _AbortoUsuario implements Exception {}

String _mensajeDeError(Object e) {
  if (e is MatixApiException) {
    if (e.statusCode == 503) {
      return 'La voz no está disponible ahora mismo. (${e.message})';
    }
    if (e.statusCode == 413) {
      return 'Hablaste muy largo. Probá decirlo en fragmentos más cortos.';
    }
    if (e.statusCode == 0) {
      return 'No pude llegar al cerebro. ¿Está corriendo?';
    }
    return 'Falló la voz (${e.statusCode}): ${e.message}';
  }
  if (e is StateError) return e.message;
  return 'Algo se rompió en el modo manos libres: $e';
}
