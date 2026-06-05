import 'package:flutter/services.dart';

import 'wakeword_log.dart';
import 'wakeword_modelo.dart';

/// Puente Dart ↔ foreground service nativo del wake word en segundo plano
/// (`WakeWordService.kt`). Controla iniciar/detener el service, pide la
/// excepción de optimización de batería y recibe la señal de "abrir modo de
/// voz" cuando el service trajo la app al frente por una detección.
///
/// Solo Android. En otras plataformas los `invokeMethod` lanzan
/// MissingPluginException, que atrapamos: la escucha en segundo plano no existe
/// ahí y la app sigue normal.
class WakeWordBgService {
  WakeWordBgService() {
    _canal.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onWakeWordBackground':
          wlog('bg: la app volvió al frente por detección');
          _alAbrir?.call();
        case 'onOverlayAbrir':
          _alOverlayAbrir?.call();
        case 'onOverlayCerrar':
          _alOverlayCerrar?.call();
      }
      return null;
    });
  }

  static const _canal = MethodChannel('dev.matix.matix/wakeword_bg');
  void Function()? _alAbrir;
  void Function()? _alOverlayAbrir;
  void Function()? _alOverlayCerrar;

  /// Qué hacer cuando el wake word de fondo trae la app al frente (abrir manos
  /// libres). Lo fija el root de la app.
  void registrarAlAbrir(void Function() cb) => _alAbrir = cb;

  /// Toques del overlay flotante: "Abrir" (expandir a Matix completo) y "Cerrar"
  /// (terminar la sesión). Los fija el controlador del overlay.
  void registrarOverlay({
    required void Function() alAbrir,
    required void Function() alCerrar,
  }) {
    _alOverlayAbrir = alAbrir;
    _alOverlayCerrar = alCerrar;
  }

  /// Muestra la burbuja flotante del wake (overlay) con un estado inicial.
  /// Devuelve false si no hay permiso "mostrar sobre otras apps" (degrada).
  Future<bool> overlayMostrar(String estado) async {
    try {
      return (await _canal
              .invokeMethod<bool>('overlayMostrar', {'estado': estado})) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Cambia el texto de estado del overlay (escuchando/pensando/hablando).
  Future<void> overlayActualizar(String estado) async {
    try {
      await _canal.invokeMethod('overlayActualizar', {'estado': estado});
    } catch (_) {}
  }

  /// Quita la burbuja.
  Future<void> overlayOcultar() async {
    try {
      await _canal.invokeMethod('overlayOcultar');
    } catch (_) {}
  }

  /// Manda Matix al fondo (el juego vuelve al frente, la burbuja queda encima).
  Future<void> enviarAlFondo() async {
    try {
      await _canal.invokeMethod('enviarAlFondo');
    } catch (_) {}
  }

  /// Trae Matix al frente (el overlay tocó "Abrir" → pantalla completa).
  Future<void> traerAlFrente() async {
    try {
      await _canal.invokeMethod('traerAlFrente');
    } catch (_) {}
  }

  Future<void> iniciar({
    required double umbral,
    String clasificador = WakeWordModelo.archivo,
  }) async {
    try {
      await _canal.invokeMethod('iniciar', {
        'umbral': umbral,
        'clasificador': clasificador,
      });
      wlog('bg: service iniciado (umbral=$umbral)');
    } catch (e) {
      wlog('bg: error al iniciar service: $e');
    }
  }

  Future<void> detener() async {
    try {
      await _canal.invokeMethod('detener');
    } catch (e) {
      wlog('bg: error al detener service: $e');
    }
  }

  /// Pide la excepción de optimización de batería (abre el diálogo del sistema).
  Future<bool> pedirIgnorarBateria() async {
    try {
      return (await _canal.invokeMethod<bool>('pedirIgnorarBateria')) ?? false;
    } catch (e) {
      wlog('bg: error pedir excepción de batería: $e');
      return false;
    }
  }

  Future<bool> estaIgnorandoBateria() async {
    try {
      return (await _canal.invokeMethod<bool>('estaIgnorandoBateria')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// ¿La app puede usar full-screen intents para AUTO-LANZAR el modo de voz
  /// desde background al detectar? (Android 14+ requiere permiso especial.)
  Future<bool> puedeFullScreenIntent() async {
    try {
      return (await _canal.invokeMethod<bool>('puedeFullScreenIntent')) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Abre los Ajustes del sistema para conceder el full-screen intent.
  Future<void> pedirFullScreenIntent() async {
    try {
      await _canal.invokeMethod('pedirFullScreenIntent');
    } catch (e) {
      wlog('bg: error pedir full-screen intent: $e');
    }
  }

  /// ¿Tiene "mostrar sobre otras apps" (overlay)? Exime del bloqueo de
  /// lanzamiento de actividades desde background (clave en Honor/MagicOS).
  Future<bool> puedeOverlay() async {
    try {
      return (await _canal.invokeMethod<bool>('puedeOverlay')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Abre los Ajustes para conceder "mostrar sobre otras apps".
  Future<void> pedirOverlay() async {
    try {
      await _canal.invokeMethod('pedirOverlay');
    } catch (e) {
      wlog('bg: error pedir overlay: $e');
    }
  }

  /// Al arrancar: ¿la app la lanzó el wake word de fondo? (se consume una vez)
  Future<bool> consumirApertura() async {
    try {
      return (await _canal.invokeMethod<bool>('consumirAperturaWakeWord')) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
