import 'package:shared_preferences/shared_preferences.dart';

/// Config CENTRALIZADA de la voz de Matix: UNA sola fuente de verdad que
/// TODOS los puntos de voz leen (chat / manos libres / cámara / briefing /
/// cierre). Antes cada punto configuraba su propio TTS y podían divergir;
/// ahora todos aplican esta `VozConfig` en `VozDispositivo.preparar()`.
///
/// La voz es la del DISPOSITIVO (flutter_tts, gratis). Se persiste en
/// `SharedPreferences` para que sobreviva reinicios y se comparta entre los
/// (varios) motores TTS de la app.
class VozConfig {
  const VozConfig({
    this.voiceName,
    this.locale,
    this.pitch = pitchDefault,
    this.rate = rateDefault,
  });

  /// Nombre EXACTO de la voz del device (de `flutter_tts.getVoices`), o null
  /// para usar la mejor voz en español que resuelva el motor por idioma.
  final String? voiceName;

  /// Locale de la voz elegida (`es-419`, `es-ES`, …). Va de la mano de
  /// `voiceName` (flutter_tts.setVoice espera {name, locale}).
  final String? locale;

  /// Tono. 1.0 = neutro. Rango útil ~0.5–2.0.
  final double pitch;

  /// Velocidad de habla. El default del proyecto (0.55) es un toque por encima
  /// del default lento de Android, claro para narración y conversación.
  final double rate;

  static const double pitchDefault = 1.0;
  static const double rateDefault = 0.55;
  static const double pitchMin = 0.5;
  static const double pitchMax = 2.0;
  static const double rateMin = 0.3;
  static const double rateMax = 1.0;

  bool get tieneVozElegida => (voiceName ?? '').isNotEmpty;

  VozConfig copyWith({
    String? voiceName,
    String? locale,
    double? pitch,
    double? rate,
    bool limpiarVoz = false,
  }) {
    return VozConfig(
      voiceName: limpiarVoz ? null : (voiceName ?? this.voiceName),
      locale: limpiarVoz ? null : (locale ?? this.locale),
      pitch: pitch ?? this.pitch,
      rate: rate ?? this.rate,
    );
  }

  static double _clamp(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);

  /// Pitch/rate recortados a su rango válido (defensa ante valores corruptos).
  VozConfig get saneada => VozConfig(
        voiceName: voiceName,
        locale: locale,
        pitch: _clamp(pitch, pitchMin, pitchMax),
        rate: _clamp(rate, rateMin, rateMax),
      );
}

/// Persistencia de la `VozConfig` en `SharedPreferences`. Inyectable-friendly:
/// los tests usan `SharedPreferences.setMockInitialValues`.
class VozPrefs {
  static const _kVoiceName = 'voz_matix_voice_name';
  static const _kLocale = 'voz_matix_locale';
  static const _kPitch = 'voz_matix_pitch';
  static const _kRate = 'voz_matix_rate';

  Future<VozConfig> cargar() async {
    final p = await SharedPreferences.getInstance();
    return VozConfig(
      voiceName: p.getString(_kVoiceName),
      locale: p.getString(_kLocale),
      pitch: p.getDouble(_kPitch) ?? VozConfig.pitchDefault,
      rate: p.getDouble(_kRate) ?? VozConfig.rateDefault,
    ).saneada;
  }

  Future<void> guardar(VozConfig cfg) async {
    final c = cfg.saneada;
    final p = await SharedPreferences.getInstance();
    if ((c.voiceName ?? '').isEmpty) {
      await p.remove(_kVoiceName);
      await p.remove(_kLocale);
    } else {
      await p.setString(_kVoiceName, c.voiceName!);
      if ((c.locale ?? '').isNotEmpty) {
        await p.setString(_kLocale, c.locale!);
      } else {
        await p.remove(_kLocale);
      }
    }
    await p.setDouble(_kPitch, c.pitch);
    await p.setDouble(_kRate, c.rate);
  }
}

/// Una voz del dispositivo, normalizada desde el `Map` que da
/// `flutter_tts.getVoices` (`{name, locale}` y a veces más campos).
class VozDisponible {
  const VozDisponible({required this.name, required this.locale});
  final String name;
  final String locale;

  /// `true` si la voz es de español (cualquier región).
  bool get esEspanol => locale.toLowerCase().startsWith('es');

  /// Heurística "voz mejorada": Google marca las de mejor calidad con sufijos
  /// como `-language` / `network` / `enhanced` / un índice alto. No es exacta,
  /// pero ordena razonablemente para sugerir la mejor por defecto.
  bool get pareceMejorada {
    final n = name.toLowerCase();
    return n.contains('network') ||
        n.contains('enhanced') ||
        n.contains('neural') ||
        n.contains('wavenet') ||
        n.contains('-x-') ||
        n.contains('local'); // las locales descargadas suelen sonar mejor
  }
}

/// Normaliza la lista cruda de `flutter_tts.getVoices` (una lista de mapas
/// `{name, locale}`) a `VozDisponible`. PURA y testeable.
List<VozDisponible> normalizarVoces(List<dynamic>? crudas) {
  if (crudas == null) return const [];
  final out = <VozDisponible>[];
  for (final v in crudas) {
    if (v is Map) {
      final name = (v['name'] ?? v['voiceURI'] ?? '').toString();
      final locale = (v['locale'] ?? v['language'] ?? '').toString();
      if (name.isNotEmpty) out.add(VozDisponible(name: name, locale: locale));
    }
  }
  return out;
}

/// Solo las voces en español, ordenadas: primero las que parecen mejoradas,
/// luego por preferencia de región (Latam antes que España, que es lo que el
/// user usa), luego por nombre. PURA y testeable.
List<VozDisponible> vocesEspanol(List<VozDisponible> voces) {
  const ordenRegion = ['es-419', 'es-us', 'es-mx', 'es-pe', 'es-co', 'es-ar', 'es-es'];
  int rankRegion(String locale) {
    final l = locale.toLowerCase();
    final i = ordenRegion.indexWhere((r) => l == r);
    return i == -1 ? ordenRegion.length : i;
  }

  final es = voces.where((v) => v.esEspanol).toList();
  es.sort((a, b) {
    if (a.pareceMejorada != b.pareceMejorada) {
      return a.pareceMejorada ? -1 : 1; // mejoradas primero
    }
    final ra = rankRegion(a.locale), rb = rankRegion(b.locale);
    if (ra != rb) return ra.compareTo(rb);
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return es;
}

/// La MEJOR voz en español disponible (o null si no hay ninguna en es). Es la
/// primera de `vocesEspanol`. Se usa como default cuando el usuario no eligió
/// una explícitamente. PURA y testeable.
VozDisponible? mejorVozEspanol(List<VozDisponible> voces) {
  final es = vocesEspanol(voces);
  return es.isEmpty ? null : es.first;
}
