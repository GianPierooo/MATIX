import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/eventos/domain/evento.dart';
import 'package:matix/features/nudges/domain/nudges.dart' show HorasSilencio;
import 'package:matix/features/planificador/domain/disponibilidad.dart';
import 'package:matix/features/planificador/domain/planificador.dart';

/// Tests de la disponibilidad por día (Fase 3): que cada día tenga su
/// propia ventana, que un evento ocupe el hueco, y que el silencio y los
/// días no disponibles se respeten.

Evento _ev(DateTime ini, DateTime fin) => Evento(
      id: 'e',
      titulo: 'Evento',
      iniciaEn: ini,
      terminaEn: fin,
      creadoEn: DateTime(2026, 1, 1),
      actualizadoEn: DateTime(2026, 1, 1),
    );

void main() {
  const silencio = HorasSilencio(); // 22–8

  group('DisponibilidadSemanal por día', () {
    test('ventana distinta por día (lun-vie 18-22, sáb-dom 9-13)', () {
      final disp = DisponibilidadSemanal({
        for (var d = 1; d <= 5; d++)
          d: const DisponibilidadDia(inicio: 18, fin: 22),
        6: const DisponibilidadDia(inicio: 9, fin: 13),
        7: const DisponibilidadDia(inicio: 9, fin: 13),
      });
      // 2026-06-10 es miércoles (día 3) → 18-22.
      expect(disp.ventanaDe(DateTime(2026, 6, 10))!.inicio, 18);
      expect(disp.ventanaDe(DateTime(2026, 6, 10))!.fin, 22);
      // 2026-06-13 es sábado (día 6) → 9-13.
      expect(disp.ventanaDe(DateTime(2026, 6, 13))!.inicio, 9);
      expect(disp.ventanaDe(DateTime(2026, 6, 13))!.fin, 13);
    });

    test('día no disponible → sin ventana ni huecos', () {
      final disp = DisponibilidadSemanal({
        3: const DisponibilidadDia(activo: false),
      });
      final dia = DateTime(2026, 6, 10); // miércoles (día 3)
      expect(disp.ventanaDe(dia), isNull);
      final huecos = huecosDisponibles(
        dia: dia,
        ventana: disp.ventanaDe(dia),
        silencio: silencio,
        eventos: const [],
      );
      expect(huecos, isEmpty);
    });
  });

  group('huecosDisponibles', () {
    test('un evento ocupa el hueco (lo parte en dos)', () {
      final dia = DateTime(2026, 6, 13); // sábado
      final huecos = huecosDisponibles(
        dia: dia,
        ventana: const VentanaTrabajo(inicio: 9, fin: 13),
        silencio: silencio,
        eventos: [
          _ev(DateTime(2026, 6, 13, 10, 0), DateTime(2026, 6, 13, 11, 0)),
        ],
      );
      // 9–13 menos 10–11 → [9–10] y [11–13].
      expect(huecos.length, 2);
      expect(huecos[0].inicio, DateTime(2026, 6, 13, 9, 0));
      expect(huecos[0].fin, DateTime(2026, 6, 13, 10, 0));
      expect(huecos[1].inicio, DateTime(2026, 6, 13, 11, 0));
      expect(huecos[1].fin, DateTime(2026, 6, 13, 13, 0));
    });

    test('recorta el silencio que entra en la ventana', () {
      final dia = DateTime(2026, 6, 13);
      // Ventana 20–24 con silencio 22–8 → solo 20–22 queda libre.
      final huecos = huecosDisponibles(
        dia: dia,
        ventana: const VentanaTrabajo(inicio: 20, fin: 24),
        silencio: silencio,
        eventos: const [],
      );
      for (final h in huecos) {
        expect(h.fin.isAfter(DateTime(2026, 6, 13, 22, 0)), isFalse);
      }
    });

    test('sin disponibilidad ese día (ventana null) → vacío', () {
      final huecos = huecosDisponibles(
        dia: DateTime(2026, 6, 13),
        ventana: null,
        silencio: silencio,
        eventos: const [],
      );
      expect(huecos, isEmpty);
    });
  });
}
