// Verifica el manifiesto Android para multi-window / ventana flotante: que la
// activity principal sea redimensionable y maneje los cambios de config sin
// recrearse al cambiar de tamaño (clave para que el atajo flotante de Honor
// ponga Matix como ventana sobre un juego sin reiniciar la app).
//
// Es un test de archivo (dart:io): el gate del CI lo corre con `flutter test`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // `flutter test` corre con cwd = directorio `app/`.
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  // Aísla el bloque de la <activity> principal (MainActivity).
  final actIdx = manifest.indexOf('.MainActivity');
  final bloque = manifest.substring(
    manifest.lastIndexOf('<activity', actIdx),
    manifest.indexOf('>', actIdx) + 1,
  );

  group('AndroidManifest · multi-window', () {
    test('MainActivity es resizeableActivity="true"', () {
      expect(bloque, contains('android:resizeableActivity="true"'));
    });

    test('configChanges cubre los cambios de tamaño (no recrea en resize)', () {
      final cc = RegExp('android:configChanges="([^"]+)"').firstMatch(bloque);
      expect(cc, isNotNull, reason: 'falta android:configChanges');
      final flags = cc!.group(1)!;
      for (final f in [
        'orientation',
        'screenSize',
        'smallestScreenSize',
        'screenLayout',
        'keyboardHidden',
        'uiMode',
        'density',
      ]) {
        expect(flags, contains(f), reason: 'configChanges sin "$f"');
      }
    });

    test('singleTop: reusa la instancia (no apila ventanas)', () {
      expect(bloque, contains('android:launchMode="singleTop"'));
    });
  });

  group('AndroidManifest · permiso de overlay', () {
    test('declara SYSTEM_ALERT_WINDOW (mostrar sobre otras apps)', () {
      expect(
        manifest,
        contains('android.permission.SYSTEM_ALERT_WINDOW'),
      );
    });
  });
}
