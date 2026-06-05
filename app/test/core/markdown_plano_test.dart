import 'package:flutter_test/flutter_test.dart';
import 'package:matix/core/markdown_plano.dart';

void main() {
  group('limpiarMarkdown', () {
    test('quita negrita con doble asterisco', () {
      expect(limpiarMarkdown('esto es **muy** importante'),
          'esto es muy importante');
    });

    test('quita itálica con asterisco simple', () {
      expect(limpiarMarkdown('algo *así* nomás'), 'algo así nomás');
    });

    test('quita negrita+itálica combinadas (triple)', () {
      expect(limpiarMarkdown('***fuerte***'), 'fuerte');
    });

    test('varias negritas en la misma línea', () {
      expect(limpiarMarkdown('**uno** y **dos**'), 'uno y dos');
    });

    test('quita encabezados de título', () {
      expect(limpiarMarkdown('## Resumen\nhola'), 'Resumen\nhola');
    });

    test('viñeta con asterisco se vuelve guion', () {
      expect(limpiarMarkdown('* item uno\n* item dos'),
          '- item uno\n- item dos');
    });

    test('quita código en línea y guion bajo de énfasis', () {
      expect(limpiarMarkdown('usa `flutter test` ya'), 'usa flutter test ya');
      expect(limpiarMarkdown('algo _enfatizado_ aquí'), 'algo enfatizado aquí');
    });

    test('no toca multiplicación a*b ni snake_case', () {
      expect(limpiarMarkdown('2 * 3 y a*b'), '2 * 3 y a*b');
      expect(limpiarMarkdown('mi_variable_larga'), 'mi_variable_larga');
    });

    test('preserva enlaces markdown intactos (los abre TextoConEnlaces)', () {
      expect(limpiarMarkdown('mira [Binance](https://binance.com) ya'),
          'mira [Binance](https://binance.com) ya');
    });

    test('no rompe una URL suelta con guion bajo dentro', () {
      const url = 'https://x.com/a_b_c';
      expect(limpiarMarkdown('fuente: $url fin'), 'fuente: $url fin');
    });

    test('negrita pegada a una URL: limpia el texto, respeta la URL', () {
      expect(
        limpiarMarkdown('**Fuente:** https://x.com/a_b'),
        'Fuente: https://x.com/a_b',
      );
    });

    test('texto sin marcas vuelve igual (atajo)', () {
      const s = 'hola, ¿cómo vamos hoy?';
      expect(limpiarMarkdown(s), s);
    });

    test('vacío vuelve vacío', () {
      expect(limpiarMarkdown(''), '');
    });

    test('es idempotente', () {
      const crudo = '**Hola** _causa_, usa `código` y ## título';
      final una = limpiarMarkdown(crudo);
      expect(limpiarMarkdown(una), una);
      expect(una.contains('*'), isFalse);
      expect(una.contains('#'), isFalse);
    });

    test('negrita sin cerrar: no deja asteriscos sueltos', () {
      expect(limpiarMarkdown('quedó **a medias').contains('*'), isFalse);
    });
  });
}
