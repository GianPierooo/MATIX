import 'package:shared_preferences/shared_preferences.dart';

import 'wakeword_pipeline.dart';

/// Preferencia local de la palabra de activación ("oye Matix").
///
/// Es estado del DISPOSITIVO, no del hub: si este teléfono escucha la palabra
/// y con qué sensibilidad es una decisión de molestia/batería de aquí, no algo
/// que deba viajar a Supabase. Por eso vive en SharedPreferences (igual que el
/// briefing matutino), no en el cerebro.
class WakeWordPrefs {
  static const _kActivo = 'wakeword_activo';
  static const _kUmbral = 'wakeword_umbral';
  static const _kBgActivo = 'wakeword_bg_activo';
  static const _kOverlayVoz = 'wakeword_overlay_voz';

  /// Apagada por defecto: el usuario la enciende a propósito desde Ajustes
  /// (y ahí se le pide el permiso de micrófono).
  Future<bool> activo() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kActivo) ?? false;
  }

  Future<void> fijarActivo(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kActivo, v);
  }

  /// Umbral de detección configurable (0..1). Por defecto el recomendado por
  /// openWakeWord para sus modelos.
  Future<double> umbral() async {
    final p = await SharedPreferences.getInstance();
    return p.getDouble(_kUmbral) ?? WakeWordPipeline.kUmbralPorDefecto;
  }

  Future<void> fijarUmbral(double v) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kUmbral, v.clamp(0.0, 1.0));
  }

  /// Escucha en SEGUNDO PLANO (foreground service nativo). Toggle SEPARADO del
  /// wake word con la app abierta: es opt-in porque consume batería. Apagado
  /// por defecto.
  Future<bool> bgActivo() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kBgActivo) ?? false;
  }

  Future<void> fijarBgActivo(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kBgActivo, v);
  }

  /// Responder con OVERLAY flotante cuando "Oye Matix" se dispara con otra app
  /// adelante (en vez de abrir Matix a pantalla completa). Opt-in: necesita el
  /// permiso "mostrar sobre otras apps". Apagado por defecto (degrada a
  /// fullscreen, el comportamiento clásico).
  Future<bool> overlayVoz() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kOverlayVoz) ?? false;
  }

  Future<void> fijarOverlayVoz(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOverlayVoz, v);
  }
}
