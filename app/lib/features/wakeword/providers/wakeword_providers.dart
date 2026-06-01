import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/wakeword_prefs.dart';
import '../data/wakeword_service.dart';

/// Fase del escuchador de wake word.
enum FaseWakeWord {
  /// Apagado por el usuario (o nunca encendido).
  desactivado,

  /// Micro abierto, escuchando la palabra.
  escuchando,

  /// En pausa porque el modo manos libres está usando el micro. Vuelve solo
  /// cuando manos libres termina.
  pausadoPorVoz,

  /// Encendido por el usuario pero sin permiso de micrófono.
  sinPermiso,

  /// Algo falló al arrancar (modelos/micro). Se muestra el detalle.
  error,
}

@immutable
class WakeWordEstado {
  const WakeWordEstado({this.fase = FaseWakeWord.desactivado, this.error});
  final FaseWakeWord fase;
  final String? error;

  WakeWordEstado copyWith({FaseWakeWord? fase, Object? error = _sentinel}) {
    return WakeWordEstado(
      fase: fase ?? this.fase,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }

  static const _sentinel = Object();
}

final wakeWordPrefsProvider = Provider<WakeWordPrefs>((ref) => WakeWordPrefs());

/// Servicio del escuchador. Tipado como interfaz para inyectar un fake en
/// tests (el real abre el micro y carga ONNX nativo).
final wakeWordServiceProvider = Provider<WakeWordEscucha>((ref) {
  final svc = WakeWordService();
  ref.onDispose(() => unawaited(svc.liberar()));
  return svc;
});

final wakeWordControllerProvider =
    NotifierProvider<WakeWordController, WakeWordEstado>(WakeWordController.new);

/// Orquesta el escuchador de wake word: el toggle del usuario, el ciclo de
/// vida (solo escucha con la app en primer plano) y el relevo del micrófono
/// con el modo manos libres.
///
/// El relevo se maneja desde `ManosLibresScreen` (único punto de entrada al
/// modo manos libres, sea por el botón o por la palabra): llama [pausarPorVoz]
/// al abrirse y [reanudarTrasVoz] al cerrarse. Así dos cosas nunca pelean por
/// el micro y no atamos el ciclo de vida de un provider autoDispose.
class WakeWordController extends Notifier<WakeWordEstado> {
  WakeWordEscucha get _svc => ref.read(wakeWordServiceProvider);
  WakeWordPrefs get _prefs => ref.read(wakeWordPrefsProvider);

  bool _enFrente = true;
  bool _pausadoPorVoz = false;
  VoidCallback? _alDetectar;

  @override
  WakeWordEstado build() => const WakeWordEstado();

  /// Registra qué hacer cuando se detecta la palabra (abrir manos libres). Lo
  /// fija el root de la app, que tiene el navigatorKey global.
  void registrarAlDetectar(VoidCallback cb) => _alDetectar = cb;

  Future<bool> estaActivo() => _prefs.activo();
  Future<double> umbral() => _prefs.umbral();

  /// Enciende/apaga la palabra desde Ajustes. Al encender pide el permiso de
  /// micrófono; si se niega, queda en [FaseWakeWord.sinPermiso].
  Future<void> activar(bool v) async {
    await _prefs.fijarActivo(v);
    if (v) {
      await _arrancar();
    } else {
      await _svc.detener();
      state = const WakeWordEstado(fase: FaseWakeWord.desactivado);
    }
  }

  /// La app volvió a primer plano.
  Future<void> alFrente() async {
    _enFrente = true;
    if (await _prefs.activo()) await _arrancar();
  }

  /// La app pasó a segundo plano: soltamos el micro (v1 solo escucha con la
  /// app abierta).
  Future<void> alFondo() async {
    _enFrente = false;
    await _svc.detener();
    if (state.fase == FaseWakeWord.escuchando) {
      state = const WakeWordEstado(fase: FaseWakeWord.desactivado);
    }
  }

  /// Manos libres tomó el micro: soltamos la escucha.
  void pausarPorVoz() {
    _pausadoPorVoz = true;
    unawaited(_svc.detener());
    if (state.fase == FaseWakeWord.escuchando) {
      state = state.copyWith(fase: FaseWakeWord.pausadoPorVoz);
    }
  }

  /// Manos libres terminó: retomamos la escucha si sigue encendida y la app
  /// está al frente.
  Future<void> reanudarTrasVoz() async {
    _pausadoPorVoz = false;
    if (_enFrente && await _prefs.activo()) await _arrancar();
  }

  Future<void> _arrancar() async {
    if (!_enFrente || _pausadoPorVoz) return;
    try {
      await _svc.iniciar(umbral: await _prefs.umbral(), onDeteccion: _onDeteccion);
      state = const WakeWordEstado(fase: FaseWakeWord.escuchando);
    } on PermisoWakeWordDenegado {
      state = const WakeWordEstado(fase: FaseWakeWord.sinPermiso);
    } catch (e) {
      state = WakeWordEstado(fase: FaseWakeWord.error, error: '$e');
    }
  }

  void _onDeteccion() {
    // Suelta el micro YA (antes de navegar) y avisa para abrir manos libres.
    _pausadoPorVoz = true;
    unawaited(_svc.detener());
    state = state.copyWith(fase: FaseWakeWord.pausadoPorVoz);
    _alDetectar?.call();
  }
}
