import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/eventos/domain/recordatorio_evento.dart';

void main() {
  group('etiquetaRecordatorio', () {
    test('mapea los presets exactos', () {
      expect(etiquetaRecordatorio(null), 'Sin recordatorio');
      expect(etiquetaRecordatorio(0), 'A la hora');
      expect(etiquetaRecordatorio(10), '10 minutos antes');
      expect(etiquetaRecordatorio(60), '1 hora antes');
      expect(etiquetaRecordatorio(1440), '1 día antes');
    });

    test('offset negativo se trata como sin recordatorio', () {
      expect(etiquetaRecordatorio(-5), 'Sin recordatorio');
    });

    test('offsets no-preset caen a descripción en claro', () {
      expect(etiquetaRecordatorio(45), '45 minutos antes');
      expect(etiquetaRecordatorio(120), '2 horas antes');
      expect(etiquetaRecordatorio(2880), '2 días antes');
    });
  });

  group('momentoRecordatorio', () {
    final inicia = DateTime(2026, 6, 15, 10, 0);

    test('null y negativo no producen instante', () {
      expect(momentoRecordatorio(inicia, null), isNull);
      expect(momentoRecordatorio(inicia, -1), isNull);
    });

    test('0 = a la hora del inicio', () {
      expect(momentoRecordatorio(inicia, 0), inicia);
    });

    test('resta el offset al inicio', () {
      expect(momentoRecordatorio(inicia, 10), DateTime(2026, 6, 15, 9, 50));
      expect(momentoRecordatorio(inicia, 1440), DateTime(2026, 6, 14, 10, 0));
    });
  });

  group('agendaRecordatorio', () {
    final ahora = DateTime(2026, 6, 15, 8, 0);

    test('sin offset no agenda', () {
      expect(
        agendaRecordatorio(
          inicia: DateTime(2026, 6, 15, 10, 0),
          offsetMin: null,
          ahora: ahora,
        ),
        isFalse,
      );
    });

    test('recordatorio futuro agenda', () {
      // inicia 10:00, offset 10 → recordatorio 09:50 (futuro vs 08:00).
      expect(
        agendaRecordatorio(
          inicia: DateTime(2026, 6, 15, 10, 0),
          offsetMin: 10,
          ahora: ahora,
        ),
        isTrue,
      );
    });

    test('evento ya pasado no agenda', () {
      // inicia 07:00 (antes de ahora=08:00) → recordatorio en el pasado.
      expect(
        agendaRecordatorio(
          inicia: DateTime(2026, 6, 15, 7, 0),
          offsetMin: 10,
          ahora: ahora,
        ),
        isFalse,
      );
    });

    test('recordatorio cuyo instante ya pasó aunque el evento sea futuro', () {
      // inicia 08:30, offset 60 → recordatorio 07:30 (ya pasó vs 08:00),
      // aunque el evento (08:30) todavía no ocurra.
      expect(
        agendaRecordatorio(
          inicia: DateTime(2026, 6, 15, 8, 30),
          offsetMin: 60,
          ahora: ahora,
        ),
        isFalse,
      );
    });
  });
}
