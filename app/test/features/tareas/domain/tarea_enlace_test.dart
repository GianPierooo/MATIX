// Enlace tarea ↔ bloque del plan: helpers puros del dominio Tarea para que la
// UI distinga sin pensar entre tarea AGENDADA (con bloque), tarea con
// VENCIMIENTO, tarea de BACKLOG (sin nada), y tarea COMPLETADA.
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/tareas/domain/tarea.dart';

Tarea _t({
  bool completada = false,
  DateTime? venceEn,
  DateTime? bloqueInicio,
  DateTime? bloqueFin,
}) {
  final ahora = DateTime(2026, 6, 5, 10);
  return Tarea(
    id: 'x',
    titulo: 'x',
    prioridad: Prioridad.media,
    completada: completada,
    venceEn: venceEn,
    bloqueInicio: bloqueInicio,
    bloqueFin: bloqueFin,
    creadaEn: ahora,
    actualizadaEn: ahora,
  );
}

void main() {
  group('Tarea.estaAgendada', () {
    test('true sólo si tiene bloque_inicio', () {
      expect(_t().estaAgendada, isFalse);
      expect(_t(venceEn: DateTime(2026, 6, 6)).estaAgendada, isFalse);
      expect(
        _t(bloqueInicio: DateTime(2026, 6, 5, 14)).estaAgendada,
        isTrue,
      );
    });
  });

  group('Tarea.esBacklog', () {
    test('true sin venceEn, sin bloque y no completada', () {
      expect(_t().esBacklog, isTrue);
    });

    test('false si tiene venceEn', () {
      expect(_t(venceEn: DateTime(2026, 6, 8)).esBacklog, isFalse);
    });

    test('false si está agendada (tiene bloque)', () {
      expect(
        _t(bloqueInicio: DateTime(2026, 6, 5, 14)).esBacklog,
        isFalse,
      );
    });

    test('false si está completada', () {
      expect(_t(completada: true).esBacklog, isFalse);
    });
  });

  group('Tarea.plazoEfectivo (regresión)', () {
    test('prefiere bloqueFin sobre venceEn (es el plazo propio del día)', () {
      final t = _t(
        venceEn: DateTime(2026, 6, 10, 23, 59),
        bloqueInicio: DateTime(2026, 6, 5, 14),
        bloqueFin: DateTime(2026, 6, 5, 15),
      );
      expect(t.plazoEfectivo, DateTime(2026, 6, 5, 15));
    });

    test('cae a venceEn si no hay bloque', () {
      final t = _t(venceEn: DateTime(2026, 6, 10, 23, 59));
      expect(t.plazoEfectivo, DateTime(2026, 6, 10, 23, 59));
    });

    test('null si no hay nada (backlog)', () {
      expect(_t().plazoEfectivo, isNull);
    });
  });
}
