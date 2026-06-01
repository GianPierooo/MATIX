import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/wakeword/data/wakeword_pipeline.dart';
import 'package:matix/features/wakeword/data/wakeword_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('por defecto: apagada y umbral recomendado', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = WakeWordPrefs();
    expect(await prefs.activo(), isFalse);
    expect(await prefs.umbral(), WakeWordPipeline.kUmbralPorDefecto);
  });

  test('persiste el toggle y el umbral', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = WakeWordPrefs();

    await prefs.fijarActivo(true);
    expect(await prefs.activo(), isTrue);

    await prefs.fijarUmbral(0.7);
    expect(await prefs.umbral(), 0.7);
  });

  test('escucha en segundo plano: apagada por defecto, persiste', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = WakeWordPrefs();
    expect(await prefs.bgActivo(), isFalse);
    await prefs.fijarBgActivo(true);
    expect(await prefs.bgActivo(), isTrue);
  });

  test('el umbral se recorta a 0..1', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = WakeWordPrefs();
    await prefs.fijarUmbral(1.8);
    expect(await prefs.umbral(), 1.0);
    await prefs.fijarUmbral(-0.5);
    expect(await prefs.umbral(), 0.0);
  });
}
