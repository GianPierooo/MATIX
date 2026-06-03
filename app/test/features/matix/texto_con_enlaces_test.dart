import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/matix/presentation/widgets/texto_con_enlaces.dart';

void main() {
  group('parsearEnlaces', () {
    test('texto sin enlaces → un solo segmento plano', () {
      final s = parsearEnlaces('hola qué tal');
      expect(s.length, 1);
      expect(s.first.esEnlace, isFalse);
      expect(s.first.texto, 'hola qué tal');
    });

    test('enlace markdown muestra el texto y guarda la url', () {
      final s = parsearEnlaces('mira [Binance](https://binance.com) ahora');
      expect(s.length, 3);
      expect(s[0].texto, 'mira ');
      expect(s[1].esEnlace, isTrue);
      expect(s[1].texto, 'Binance');
      expect(s[1].url, 'https://binance.com');
      expect(s[2].texto, ' ahora');
    });

    test('url suelta se vuelve enlace con la url como texto', () {
      final s = parsearEnlaces('fuente: https://x.com/a/b fin');
      final enlace = s.firstWhere((e) => e.esEnlace);
      expect(enlace.texto, 'https://x.com/a/b');
      expect(enlace.url, 'https://x.com/a/b');
    });

    test('puntuación final pegada a la url queda como texto plano', () {
      final s = parsearEnlaces('ver https://x.com.');
      final enlace = s.firstWhere((e) => e.esEnlace);
      expect(enlace.url, 'https://x.com');
      // El punto final no es parte del enlace.
      expect(s.last.esEnlace, isFalse);
      expect(s.last.texto.endsWith('.'), isTrue);
    });

    test('varios enlaces markdown en lista', () {
      final s = parsearEnlaces(
        '- [Uno](https://a.com)\n- [Dos](https://b.com)',
      );
      final enlaces = s.where((e) => e.esEnlace).toList();
      expect(enlaces.length, 2);
      expect(enlaces[0].url, 'https://a.com');
      expect(enlaces[1].url, 'https://b.com');
    });

    test('no confunde corchetes sin url con enlace', () {
      final s = parsearEnlaces('esto [no es] un enlace');
      expect(s.every((e) => !e.esEnlace), isTrue);
    });
  });
}
