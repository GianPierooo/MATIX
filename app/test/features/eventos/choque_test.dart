import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/eventos/domain/choque.dart';

void main() {
  group('seSolapan', () {
    DateTime t(int h, int m) => DateTime(2026, 5, 26, h, m);

    test('solape clásico', () {
      // 18:30–20:00 vs 19:00–21:00 → choque
      expect(seSolapan(t(18, 30), t(20, 0), t(19, 0), t(21, 0)), isTrue);
    });

    test('caso del usuario: clase 20:15–21:45 vs boxeo 21:00–22:00', () {
      expect(seSolapan(t(20, 15), t(21, 45), t(21, 0), t(22, 0)), isTrue);
    });

    test('tocar punta con punta no es choque', () {
      // 18:00–20:00 vs 20:00–22:00 → no choque
      expect(seSolapan(t(18, 0), t(20, 0), t(20, 0), t(22, 0)), isFalse);
    });

    test('uno contiene al otro', () {
      expect(seSolapan(t(8, 0), t(22, 0), t(12, 0), t(13, 0)), isTrue);
    });

    test('disjuntos no se solapan', () {
      expect(seSolapan(t(8, 0), t(10, 0), t(14, 0), t(16, 0)), isFalse);
    });

    test('orden invertido también detecta', () {
      expect(seSolapan(t(19, 0), t(21, 0), t(18, 30), t(20, 0)), isTrue);
    });
  });
}
