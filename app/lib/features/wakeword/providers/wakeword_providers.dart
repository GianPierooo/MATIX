import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/wakeword_crumbs.dart';
import '../data/wakeword_log.dart';
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
  const WakeWordEstado({
    this.fase = FaseWakeWord.desactivado,
    this.error,
    this.ultimoScore = 0,
    this.maxScore = 0,
  });
  final FaseWakeWord fase;
  final String? error;

  /// Último score de detección (0..1) y máximo de esta sesión de escucha.
  /// Se muestran en Ajustes para diagnosticar si "hey jarvis" cruza el umbral
  /// sin depender de logcat (que el Honor filtra).
  final double ultimoScore;
  final double maxScore;

  WakeWordEstado copyWith({
    FaseWakeWord? fase,
    Object? error = _sentinel,
    double? ultimoScore,
    double? maxScore,
  }) {
    return WakeWordEstado(
      fase: fase ?? this.fase,
      error: identical(error, _sentinel) ? this.error : error as String?,
      ultimoScore: ultimoScore ?? this.ultimoScore,
      maxScore: maxScore ?? this.maxScore,
    );
  }

  static const _sentinel = Object();
}

final wakeWordPrefsProvider = Provider<WakeWordPrefs>((ref) => WakeWordPrefs());

/// FUENTE ÚNICA DE VERDAD del relevo de micrófono: ¿hay un modo voz (manos
/// libres) activo ahora mismo?
///
/// La fija `ManosLibresScreen`: `true` al abrirse, `false` al cerrarse por
/// CUALQUIER vía (completar, cancelar, botón atrás, navegar a otra pantalla,
/// salir). El listener del wake word la observa: activo → pausa; inactivo →
/// reanuda. Así el escuchador nunca queda pegado en pausa, sin importar cómo
/// se salga del modo voz.
final modoVozActivoProvider = StateProvider<bool>((ref) => false);

/// Migajas de activación (diagnóstico de crash nativo sin USB). Compartidas
/// entre el servicio (las escribe) y el controller (las lee al arrancar).
final wakeWordCrumbsProvider = Provider<WakeWordCrumbs>((ref) => WakeWordCrumbs());

/// Servicio del escuchador. Tipado como interfaz para inyectar un fake en
/// tests (el real abre el micro y carga ONNX nativo).
final wakeWordServiceProvider = Provider<WakeWordEscucha>((ref) {
  final svc = WakeWordService(crumbs: ref.read(wakeWordCrumbsProvider));
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
  WakeWordCrumbs get _crumbs => ref.read(wakeWordCrumbsProvider);

  bool _enFrente = true;
  bool _pausadoPorVoz = false;
  VoidCallback? _alDetectar;

  @override
  WakeWordEstado build() {
    // Relevo de micro por fuente única de verdad: el modo voz (manos libres)
    // manda. Al activarse soltamos el micro; al desactivarse (por la vía que
    // sea) reanudamos. El listener vive lo que vive el controller (no
    // autoDispose), así que no hay fugas.
    ref.listen<bool>(modoVozActivoProvider, (anterior, activo) {
      if (activo) {
        pausarPorVoz();
      } else {
        unawaited(reanudarTrasVoz());
      }
    });
    return const WakeWordEstado();
  }

  /// Registra qué hacer cuando se detecta la palabra (abrir manos libres). Lo
  /// fija el root de la app, que tiene el navigatorKey global.
  void registrarAlDetectar(VoidCallback cb) => _alDetectar = cb;

  Future<bool> estaActivo() => _prefs.activo();
  Future<double> umbral() => _prefs.umbral();

  /// Cambia la sensibilidad EN VIVO desde el slider de Ajustes: persiste y, si
  /// está escuchando, la aplica al instante sin re-armar.
  Future<void> cambiarUmbral(double v) async {
    await _prefs.fijarUmbral(v);
    _svc.fijarUmbral(v);
  }

  /// Enciende/apaga la palabra desde Ajustes. Al encender pide el permiso de
  /// micrófono; si se niega, queda en [FaseWakeWord.sinPermiso].
  Future<void> activar(bool v) async {
    wlog('activar($v) desde Ajustes');
    try {
      await _prefs.fijarActivo(v);
      if (v) {
        // Intento MANUAL y deliberado: borramos el rastro de una muerte previa
        // para que sea un arranque limpio (el usuario está reintentando).
        await _crumbs.limpiar();
        await _arrancar();
      } else {
        await _svc.detener();
        state = const WakeWordEstado(fase: FaseWakeWord.desactivado);
      }
    } catch (e) {
      // activar() nunca debe relanzar al onChanged del Switch.
      wlog('activar(): error → $e');
      state = WakeWordEstado(fase: FaseWakeWord.error, error: '$e');
    }
  }

  /// La app volvió a primer plano.
  ///
  /// Circuit breaker: si la última activación murió a mitad (crash nativo de
  /// ONNX/micro), NO reintentamos sola al abrir — eso causaría un bucle de
  /// crashes que deja la app inusable. La dejamos desarmada, mostramos en qué
  /// paso murió, y el usuario decide si reintenta a mano.
  Future<void> alFrente() async {
    _enFrente = true;
    if (!await _prefs.activo()) return;
    final muerte = await _crumbs.muerteDeActivacion();
    if (muerte != null) {
      wlog('alFrente(): la última activación murió en "$muerte" → no auto-arranco');
      await _prefs.fijarActivo(false);
      await _crumbs.limpiar();
      state = WakeWordEstado(
        fase: FaseWakeWord.error,
        error: 'La última vez que la activé, la app se cerró en el paso '
            '"$muerte". La dejé en pausa para que la app abra bien. Vuelve a '
            'activarla si quieres reintentar.',
      );
      return;
    }
    await _arrancar();
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
    if (!_enFrente || _pausadoPorVoz) {
      wlog('_arrancar(): condiciones no dadas (frente=$_enFrente, pausa=$_pausadoPorVoz)');
      return;
    }
    try {
      _scoreTicks = 0;
      await _svc.iniciar(
        umbral: await _prefs.umbral(),
        onDeteccion: _onDeteccion,
        onScore: _onScore,
      );
      state = const WakeWordEstado(fase: FaseWakeWord.escuchando);
    } on PermisoWakeWordDenegado {
      wlog('_arrancar(): permiso de micrófono denegado');
      state = const WakeWordEstado(fase: FaseWakeWord.sinPermiso);
    } catch (e) {
      // Cualquier fallo CATCHABLE (carga ONNX, micro) → estado error visible,
      // nunca crash. (Un SIGSEGV nativo no llega acá; lo delata el log.)
      wlog('_arrancar(): error → $e');
      state = WakeWordEstado(fase: FaseWakeWord.error, error: '$e');
    }
  }

  int _scoreTicks = 0;

  /// Llamado en cada inferencia con el score (0..1). Actualiza el máximo y,
  /// throttle-ado, el último score visible en Ajustes. Loguea cada ~25 ticks
  /// (~2 s) para no inundar.
  void _onScore(double s) {
    if (state.fase != FaseWakeWord.escuchando) return;
    _scoreTicks++;
    final nuevoMax = s > state.maxScore ? s : state.maxScore;
    // Refresca la UI ~2 veces/s, o siempre que haya un nuevo máximo.
    if (s > state.maxScore || _scoreTicks % 6 == 0) {
      state = state.copyWith(ultimoScore: s, maxScore: nuevoMax);
    }
    if (_scoreTicks % 25 == 0) {
      wlog('score=${s.toStringAsFixed(3)} max=${nuevoMax.toStringAsFixed(3)}');
    }
  }

  void _onDeteccion() {
    // Suelta el micro YA (antes de navegar) y avisa para abrir manos libres.
    wlog('WAKEWORD DETECTADO (score≈${state.ultimoScore.toStringAsFixed(3)}) → navegando a manos libres');
    _pausadoPorVoz = true;
    unawaited(_svc.detener());
    state = state.copyWith(fase: FaseWakeWord.pausadoPorVoz);
    if (_alDetectar == null) {
      wlog('WAKEWORD: ¡no hay callback de navegación registrado! (bug)');
    }
    _alDetectar?.call();
  }
}
