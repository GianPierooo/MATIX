import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/nudges/domain/nudges.dart';
import 'package:matix/features/tareas/domain/tarea.dart';

/// Tests de la lógica pura de nudges escalados (Urgencia-2):
/// - la escala genera más puntos cerca del plazo (no parejo),
/// - las horas de silencio corren el nudge,
/// - completar / sin plazo / silenciada cancelan (plan vacío).
/// Todo determinístico: `ahora` se pasa explícito.

Tarea _tarea({
  String id = 't1',
  DateTime? venceEn,
  bool completada = false,
}) {
  final base = DateTime(2026, 1, 1);
  return Tarea(
    id: id,
    titulo: 'Tarea $id',
    venceEn: venceEn,
    completada: completada,
    creadaEn: base,
    actualizadaEn: base,
  );
}

void main() {
  group('enSilencio (default 22–8)', () {
    const s = HorasSilencio();
    test('tarde y madrugada están en silencio', () {
      expect(enSilencio(DateTime(2026, 6, 9, 23, 0), s), isTrue);
      expect(enSilencio(DateTime(2026, 6, 9, 3, 0), s), isTrue);
      expect(enSilencio(DateTime(2026, 6, 9, 7, 59), s), isTrue);
    });
    test('el día está permitido', () {
      expect(enSilencio(DateTime(2026, 6, 9, 8, 0), s), isFalse);
      expect(enSilencio(DateTime(2026, 6, 9, 15, 0), s), isFalse);
      expect(enSilencio(DateTime(2026, 6, 9, 21, 59), s), isFalse);
    });
  });

  group('correrFueraDeSilencio', () {
    const s = HorasSilencio();
    test('de noche se corre a las 08:00 del día siguiente', () {
      expect(correrFueraDeSilencio(DateTime(2026, 6, 9, 23, 0), s),
          DateTime(2026, 6, 10, 8, 0));
    });
    test('de madrugada se corre a las 08:00 del mismo día', () {
      expect(correrFueraDeSilencio(DateTime(2026, 6, 9, 3, 0), s),
          DateTime(2026, 6, 9, 8, 0));
    });
    test('de día no se mueve', () {
      final t = DateTime(2026, 6, 9, 15, 0);
      expect(correrFueraDeSilencio(t, s), t);
    });
  });

  group('calendarioNudges', () {
    // Plazo lejano y de día, para que no haya corrimientos por silencio.
    final vence = DateTime(2026, 6, 10, 15, 0);
    final ahora = DateTime(2026, 5, 25, 9, 0);

    test('la intensidad controla cuántos puntos', () {
      expect(
          calendarioNudges(vence, ahora, intensidad: IntensidadNudge.suave)
              .length,
          2);
      expect(
          calendarioNudges(vence, ahora, intensidad: IntensidadNudge.normal)
              .length,
          4);
      expect(
          calendarioNudges(vence, ahora, intensidad: IntensidadNudge.fuerte)
              .length,
          6);
    });

    test('la escala agrupa más puntos cerca del plazo (intervalos bajan)', () {
      final p =
          calendarioNudges(vence, ahora, intensidad: IntensidadNudge.fuerte);
      // Los huecos entre nudges consecutivos no crecen al acercarse.
      for (var i = 2; i < p.length; i++) {
        final previo = p[i - 1].difference(p[i - 2]);
        final actual = p[i].difference(p[i - 1]);
        expect(actual <= previo, isTrue,
            reason: 'el hueco $i debería ser <= al anterior');
      }
      // Y hay más nudges en las últimas 24 h que antes.
      final corte = vence.subtract(const Duration(hours: 24));
      final cerca = p.where((d) => !d.isBefore(corte)).length;
      final lejos = p.where((d) => d.isBefore(corte)).length;
      expect(cerca > lejos, isTrue);
    });

    test('las horas de silencio corren el nudge dentro del calendario', () {
      // Ventana de silencio diurna a propósito: 14–16. El nudge de "3 h
      // antes" cae 15:00 → se corre a 16:00.
      final v = DateTime(2026, 6, 10, 18, 0);
      final a = DateTime(2026, 6, 1, 9, 0);
      final p = calendarioNudges(
        v,
        a,
        intensidad: IntensidadNudge.suave, // [1 día, 3 h]
        silencio: const HorasSilencio(inicio: 14, fin: 16),
      );
      expect(p.contains(DateTime(2026, 6, 10, 16, 0)), isTrue);
      expect(p.contains(DateTime(2026, 6, 10, 15, 0)), isFalse);
    });

    test('descarta los puntos que ya pasaron', () {
      final ahoraCerca = DateTime(2026, 5, 25, 12, 0);
      final venceCerca = DateTime(2026, 5, 25, 13, 30); // a 1.5 h
      final p = calendarioNudges(venceCerca, ahoraCerca,
          intensidad: IntensidadNudge.fuerte);
      // Solo sobrevive el de "1 h antes" (12:30); el resto ya pasó.
      expect(p, [DateTime(2026, 5, 25, 12, 30)]);
    });
  });

  group('cuerpoNudge', () {
    test('referencia el tiempo restante, activador', () {
      expect(
          cuerpoNudge(
              DateTime(2026, 6, 10, 15, 0), DateTime(2026, 6, 10, 12, 0)),
          'Vence en 3 horas');
      expect(
          cuerpoNudge(
              DateTime(2026, 6, 10, 15, 0), DateTime(2026, 6, 9, 15, 0)),
          'Vence en 1 día');
      expect(
          cuerpoNudge(
              DateTime(2026, 6, 10, 15, 0), DateTime(2026, 6, 10, 14, 30)),
          'Vence en 30 minutos');
    });
  });

  group('planNudges', () {
    final ahora = DateTime(2026, 5, 25, 9, 0);
    final vence = DateTime(2026, 6, 10, 15, 0);

    test('tarea con plazo → plan con ids distintos y cuerpo', () {
      final plan = planNudges(_tarea(venceEn: vence), ahora,
          intensidad: IntensidadNudge.normal);
      expect(plan.length, 4);
      expect(plan.map((n) => n.id).toSet().length, 4); // ids únicos
      expect(plan.first.cuerpo.startsWith('Vence en '), isTrue);
    });

    test('completar cancela: plan vacío', () {
      final plan =
          planNudges(_tarea(venceEn: vence, completada: true), ahora);
      expect(plan, isEmpty);
    });

    test('sin plazo: plan vacío', () {
      expect(planNudges(_tarea(venceEn: null), ahora), isEmpty);
    });

    test('silenciada: plan vacío', () {
      final plan = planNudges(_tarea(venceEn: vence), ahora, silenciada: true);
      expect(plan, isEmpty);
    });
  });
}
