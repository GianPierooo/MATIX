import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/matix/data/voz_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Config CENTRALIZADA de la voz: round-trip en prefs, saneado de rangos, y las
/// heurísticas PURAS de selección de la mejor voz en español.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('VozConfig saneada', () {
    test('recorta pitch y rate fuera de rango', () {
      final c = const VozConfig(pitch: 9.0, rate: 9.0).saneada;
      expect(c.pitch, VozConfig.pitchMax);
      expect(c.rate, VozConfig.rateMax);
      final c2 = const VozConfig(pitch: -1, rate: -1).saneada;
      expect(c2.pitch, VozConfig.pitchMin);
      expect(c2.rate, VozConfig.rateMin);
    });

    test('defaults razonables', () {
      const c = VozConfig();
      expect(c.pitch, VozConfig.pitchDefault);
      expect(c.rate, VozConfig.rateDefault);
      expect(c.tieneVozElegida, isFalse);
    });
  });

  group('VozPrefs round-trip', () {
    test('por defecto: sin voz elegida, defaults de pitch/rate', () async {
      final cfg = await VozPrefs().cargar();
      expect(cfg.voiceName, isNull);
      expect(cfg.pitch, VozConfig.pitchDefault);
      expect(cfg.rate, VozConfig.rateDefault);
    });

    test('guarda y relee voz + pitch + rate', () async {
      final prefs = VozPrefs();
      await prefs.guardar(const VozConfig(
        voiceName: 'es-es-x-eed-network',
        locale: 'es-ES',
        pitch: 1.2,
        rate: 0.7,
      ));
      final cfg = await prefs.cargar();
      expect(cfg.voiceName, 'es-es-x-eed-network');
      expect(cfg.locale, 'es-ES');
      expect(cfg.pitch, closeTo(1.2, 0.0001));
      expect(cfg.rate, closeTo(0.7, 0.0001));
      expect(cfg.tieneVozElegida, isTrue);
    });

    test('limpiar la voz vuelve a "automática" (sin voiceName)', () async {
      final prefs = VozPrefs();
      await prefs.guardar(const VozConfig(voiceName: 'x', locale: 'es-ES'));
      await prefs.guardar(const VozConfig().copyWith(limpiarVoz: true, pitch: 1.1));
      final cfg = await prefs.cargar();
      expect(cfg.voiceName, isNull);
      expect(cfg.pitch, closeTo(1.1, 0.0001));
    });

    test('guarda recortando rangos corruptos', () async {
      final prefs = VozPrefs();
      await prefs.guardar(const VozConfig(pitch: 50, rate: 50));
      final cfg = await prefs.cargar();
      expect(cfg.pitch, VozConfig.pitchMax);
      expect(cfg.rate, VozConfig.rateMax);
    });
  });

  group('normalizarVoces', () {
    test('extrae name/locale y descarta lo inválido', () {
      final v = normalizarVoces([
        {'name': 'es-419-x-net', 'locale': 'es-419'},
        {'name': 'en-US-default', 'locale': 'en-US'},
        {'locale': 'es-ES'}, // sin name → descartada
        'basura',
      ]);
      expect(v.length, 2);
      expect(v.first.name, 'es-419-x-net');
    });

    test('tolera null', () => expect(normalizarVoces(null), isEmpty));
  });

  group('vocesEspanol / mejorVozEspanol', () {
    final voces = [
      const VozDisponible(name: 'en-US-voice', locale: 'en-US'),
      const VozDisponible(name: 'es-es-basica', locale: 'es-ES'),
      const VozDisponible(name: 'es-419-x-network', locale: 'es-419'), // mejorada + Latam
      const VozDisponible(name: 'es-mx-basica', locale: 'es-MX'),
    ];

    test('filtra solo español', () {
      final es = vocesEspanol(voces);
      expect(es.every((v) => v.esEspanol), isTrue);
      expect(es.length, 3);
    });

    test('mejor voz: mejorada + Latam primero', () {
      final mejor = mejorVozEspanol(voces);
      expect(mejor, isNotNull);
      expect(mejor!.name, 'es-419-x-network');
    });

    test('sin voces es → null', () {
      expect(mejorVozEspanol([
        const VozDisponible(name: 'en', locale: 'en-US'),
      ]), isNull);
    });

    test('ordena Latam antes que España cuando ninguna es mejorada', () {
      final es = vocesEspanol([
        const VozDisponible(name: 'a', locale: 'es-ES'),
        const VozDisponible(name: 'b', locale: 'es-MX'),
      ]);
      expect(es.first.locale, 'es-MX');
    });
  });
}
