import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/matix/data/pantalla_aplanado.dart';

/// Tier C.0 · percepción: la función de aplanado del árbol de pantalla es pura,
/// así que se testea con árboles JSON sintéticos (sin device).

void main() {
  group('aplanarPantalla', () {
    test('captura sin contenido (ok:false) → vacío', () {
      expect(aplanarPantalla({'ok': false, 'motivo': 'sin_ventana'}), '');
      expect(aplanarPantalla({'ok': true}), ''); // sin árbol
      expect(aplanarPantalla({'ok': true, 'arbol': 'x'}), '');
    });

    test('texto visible + descripción + jerarquía', () {
      final captura = {
        'ok': true,
        'app': 'com.whatsapp',
        'arbol': {
          't': 'WhatsApp',
          'h': [
            {'t': 'María'},
            {'t': 'Hola, ¿nos vemos?'},
          ],
        },
      };
      expect(
        aplanarPantalla(captura),
        'WhatsApp\n  María\n  Hola, ¿nos vemos?',
      );
    });

    test('los contenedores SIN texto no suman sangría (se colapsan)', () {
      // Nodo raíz sin texto: sus hijos quedan al nivel 0, no al 1.
      final captura = {
        'ok': true,
        'arbol': {
          'c': 'FrameLayout',
          'h': [
            {'t': 'Título'},
            {
              'c': 'LinearLayout',
              'h': [
                {'t': 'Detalle'},
              ],
            },
          ],
        },
      };
      expect(aplanarPantalla(captura), 'Título\nDetalle');
    });

    test('la descripción se incluye solo si difiere del texto', () {
      final conDesc = {
        'ok': true,
        'arbol': {
          'h': [
            {'t': 'Enviar', 'd': 'Enviar'}, // igual → no se repite
            {'d': 'Botón de adjuntar'}, // solo desc
            {'t': 'Foto', 'd': 'imagen recibida'}, // distinto → ambos
          ],
        },
      };
      expect(
        aplanarPantalla(conDesc),
        'Enviar\n[Botón de adjuntar]\nFoto [imagen recibida]',
      );
    });

    test('respeta el tope de líneas', () {
      final hijos = List.generate(50, (i) => {'t': 'item $i'});
      final captura = {
        'ok': true,
        'arbol': {'h': hijos},
      };
      final out = aplanarPantalla(captura, maxLineas: 10);
      expect(out.split('\n'), hasLength(10));
    });
  });

  test('appDeCaptura devuelve el paquete', () {
    expect(appDeCaptura({'app': 'com.whatsapp'}), 'com.whatsapp');
    expect(appDeCaptura({}), '');
  });
}
