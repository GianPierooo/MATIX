import 'package:flutter_test/flutter_test.dart';
import 'package:matix/core/notif_id.dart';

void main() {
  group('notifIdDe', () {
    test('uuid v4 normal cabe en 28 bits y es positivo', () {
      final id = notifIdDe('550e8400-e29b-41d4-a716-446655440000');
      expect(id, greaterThan(0));
      expect(id, lessThan(1 << 28));
    });

    test('es estable: mismo input → mismo output', () {
      const uuid = '8b1c3f0a-1234-5678-9abc-def012345678';
      expect(notifIdDe(uuid), notifIdDe(uuid));
    });

    test('uuids distintos producen ids distintos', () {
      final a = notifIdDe('11111111-2222-3333-4444-555555555555');
      final b = notifIdDe('99999999-2222-3333-4444-555555555555');
      expect(a, isNot(b));
    });

    test('string corto fallback no explota', () {
      final id = notifIdDe('abc');
      expect(id, greaterThanOrEqualTo(0));
    });
  });
}
