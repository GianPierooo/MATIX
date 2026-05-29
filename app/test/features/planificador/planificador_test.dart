import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/eventos/domain/evento.dart';
import 'package:matix/features/nudges/domain/nudges.dart' show HorasSilencio;
import 'package:matix/features/planificador/domain/planificador.dart';
import 'package:matix/features/tareas/domain/tarea.dart';

/// Tests de la lógica pura del planificador (Urgencia-3):
/// - no encima eventos existentes,
/// - respeta la ventana de trabajo,
/// - respeta las horas de silencio,
/// - reporta la sobrecarga (lo que no entra),
/// más el orden por plazo. (Que "aceptar cree los bloques" se prueba en
/// el flujo del controlador, abajo no — es lógica de repo.)

Tarea _t(String id, {DateTime? venceEn, Prioridad prioridad = Prioridad.media}) {
  final base = DateTime(2026, 1, 1);
  return Tarea(
    id: id,
    titulo: 'Tarea $id',
    venceEn: venceEn,
    prioridad: prioridad,
    creadaEn: base,
    actualizadaEn: base,
  );
}

Evento _evento(DateTime inicia, DateTime termina) {
  return Evento(
    id: 'e-${inicia.hour}',
    titulo: 'Evento',
    iniciaEn: inicia,
    terminaEn: termina,
    creadoEn: DateTime(2026, 1, 1),
    actualizadoEn: DateTime(2026, 1, 1),
  );
}

bool _solapan(DateTime ai, DateTime af, DateTime bi, DateTime bf) =>
    ai.isBefore(bf) && bi.isBefore(af);

void main() {
  // Mañana, ventana por defecto 9–21, lejos del silencio nocturno.
  final ahora = DateTime(2026, 6, 10, 9, 0);
  const ventana = VentanaTrabajo(); // 9–21
  const silencio = HorasSilencio(); // 22–8

  group('huecosLibres', () {
    test('resta los eventos del día de la ventana', () {
      final libres = huecosLibres(
        ahora: ahora,
        ventana: ventana,
        silencio: silencio,
        eventos: [
          _evento(DateTime(2026, 6, 10, 10, 0), DateTime(2026, 6, 10, 11, 0)),
        ],
      );
      // [9–10] y [11–21].
      expect(libres.length, 2);
      expect(libres[0].inicio, DateTime(2026, 6, 10, 9, 0));
      expect(libres[0].fin, DateTime(2026, 6, 10, 10, 0));
      expect(libres[1].inicio, DateTime(2026, 6, 10, 11, 0));
    });
  });

  group('planificarDia', () {
    test('no encima eventos existentes', () {
      final evIni = DateTime(2026, 6, 10, 10, 0);
      final evFin = DateTime(2026, 6, 10, 11, 0);
      final plan = planificarDia(
        tareas: [_t('a'), _t('b')],
        eventos: [_evento(evIni, evFin)],
        ahora: ahora,
        ventana: ventana,
        silencio: silencio,
        duracionesMin: {'a': 60, 'b': 60},
      );
      for (final b in plan.bloques) {
        expect(_solapan(b.inicio, b.fin, evIni, evFin), isFalse,
            reason: 'el bloque ${b.titulo} encima el evento');
      }
    });

    test('respeta la ventana de trabajo', () {
      final plan = planificarDia(
        tareas: [for (var i = 0; i < 5; i++) _t('t$i')],
        eventos: const [],
        ahora: ahora,
        ventana: ventana,
        silencio: silencio,
        duracionesMin: const {},
        duracionDefaultMin: 60,
      );
      final inicioVentana = DateTime(2026, 6, 10, 9, 0);
      final finVentana = DateTime(2026, 6, 10, 21, 0);
      for (final b in plan.bloques) {
        expect(b.inicio.isBefore(inicioVentana), isFalse);
        expect(b.fin.isAfter(finVentana), isFalse);
      }
    });

    test('respeta las horas de silencio (no agenda dentro)', () {
      // Ventana amplia 9–23 y silencio 22–8: nada debe caer en 22–23.
      final plan = planificarDia(
        tareas: [for (var i = 0; i < 20; i++) _t('t$i')],
        eventos: const [],
        ahora: ahora,
        ventana: const VentanaTrabajo(inicio: 9, fin: 23),
        silencio: silencio,
        duracionesMin: const {},
        duracionDefaultMin: 60,
      );
      final inicioSilencio = DateTime(2026, 6, 10, 22, 0);
      for (final b in plan.bloques) {
        expect(b.fin.isAfter(inicioSilencio), isFalse,
            reason: '${b.titulo} cae en el silencio');
      }
    });

    test('reporta la sobrecarga: lo que no entra queda fuera', () {
      // Ventana de 1 hora, dos tareas de 60 min → solo entra una.
      final plan = planificarDia(
        tareas: [_t('a'), _t('b')],
        eventos: const [],
        ahora: DateTime(2026, 6, 10, 9, 0),
        ventana: const VentanaTrabajo(inicio: 9, fin: 10),
        silencio: silencio,
        duracionesMin: {'a': 60, 'b': 60},
      );
      expect(plan.bloques.length, 1);
      expect(plan.sinEspacio.length, 1);
      expect(plan.nota.toLowerCase(), contains('no te entra todo'));
    });

    test('una tarea no entra antes de su plazo → sin espacio', () {
      // Plazo a las 9:30 pero la tarea dura 60 min: no entra antes.
      final plan = planificarDia(
        tareas: [_t('a', venceEn: DateTime(2026, 6, 10, 9, 30))],
        eventos: const [],
        ahora: DateTime(2026, 6, 10, 9, 0),
        ventana: ventana,
        silencio: silencio,
        duracionesMin: {'a': 60},
      );
      expect(plan.bloques, isEmpty);
      expect(plan.sinEspacio.single.tareaId, 'a');
    });

    test('ordena por plazo más cercano primero', () {
      final plan = planificarDia(
        tareas: [
          _t('lejos', venceEn: DateTime(2026, 6, 15, 12, 0)),
          _t('cerca', venceEn: DateTime(2026, 6, 11, 12, 0)),
        ],
        eventos: const [],
        ahora: ahora,
        ventana: ventana,
        silencio: silencio,
        duracionesMin: {'lejos': 60, 'cerca': 60},
      );
      expect(plan.bloques.first.tareaId, 'cerca');
    });

    test('sin tareas → nota clara, sin bloques', () {
      final plan = planificarDia(
        tareas: const [],
        eventos: const [],
        ahora: ahora,
        ventana: ventana,
        silencio: silencio,
        duracionesMin: const {},
      );
      expect(plan.bloques, isEmpty);
      expect(plan.sinEspacio, isEmpty);
    });
  });
}
