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
      if (call.method == 'onWakeWordBackground') {
        wlog('bg: la app volvió al frente por detección');
        _alAbrir?.call();
      }
      return null;
    });
  }

  static const _canal = MethodChannel('dev.matix.matix/wakeword_bg');
  void Function()? _alAbrir;

  /// Qué hacer cuando el wake word de fondo trae la app al frente (abrir manos
  /// libres). Lo fija el root de la app.
  void registrarAlAbrir(void Function() cb) => _alAbrir = cb;

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
