import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/horario/domain/plan_dia.dart';
import 'package:matix/features/widgets_inicio/domain/widget_datos.dart';

BloquePlan _b({
  required String inicio,
  required String fin,
  String titulo = 'Bloque',
  String tipo = 'trabajo',
  bool tentativo = true,
  String? proyecto,
  String? tareaId,
}) =>
    BloquePlan(
      inicio: inicio,
      fin: fin,
      titulo: titulo,
      tipo: tipo,
      tentativo: tentativo,
      proyecto: proyecto,
      tareaId: tareaId,
    );

PlanDia _plan(List<BloquePlan> bloques) => PlanDia(
      fecha: '2026-06-08',
      despierta: '07:00',
      duerme: '23:00',
      bloques: bloques,
      fuera: const [],
    );

void main() {
  final nueve = DateTime(2026, 6, 8, 9); // 09:00 → 540 min

  group('estado vacío', () {
    test('sin plan → vacío (abre Matix)', () {
      final d = construirDatosWidget(null, nueve);
      expect(d.vacio, isTrue);
      expect(d.proximo, isNull);
      expect(d.hoy, isEmpty);
    });

    test('plan sin bloques → vacío', () {
      final d = construirDatosWidget(_plan(const []), nueve);
      expect(d.vacio, isTrue);
    });
  });

  group('próximo (lo que toca ahora o lo siguiente)', () {
    test('toma el bloque que cubre AHORA', () {
      final d = construirDatosWidget(
        _plan([
          _b(inicio: '08:30', fin: '10:00', titulo: 'OneXotic: sprint',
              proyecto: 'OneXotic', tareaId: 't1'),
          _b(inicio: '11:00', fin: '12:00', titulo: 'Clase', tipo: 'clase',
              tentativo: false),
        ]),
        nueve,
      );
      expect(d.vacio, isFalse);
      expect(d.proximo!.titulo, 'OneXotic: sprint');
      expect(d.proximo!.fijo, isFalse);
      expect(d.proximo!.sub, 'OneXotic');
      expect(d.proximo!.payload, 'tarea:t1'); // deep link a la tarea
      expect(d.proximoRel, 'Ahora'); // 08:30–10:00 cubre las 09:00
      expect(d.fecha, 'lun 8 jun'); // 2026-06-08 es lunes
    });

    test('si nada cubre ahora, toma el SIGUIENTE con su relativo', () {
      final d = construirDatosWidget(
        _plan([_b(inicio: '11:00', fin: '12:00', titulo: 'Gym', tipo: 'evento',
            tentativo: false)]),
        nueve,
      );
      expect(d.proximo!.titulo, 'Gym');
      expect(d.proximo!.fijo, isTrue);
      expect(d.proximo!.sub, 'Fijo');
      expect(d.proximo!.payload, 'hoy'); // sin tareaId → abre Inicio
      expect(d.proximoRel, 'en 2 h'); // 09:00 → 11:00
    });

    test('día cerrado (nada por delante) → sin pendientes', () {
      final d = construirDatosWidget(
        _plan([_b(inicio: '07:00', fin: '08:00', titulo: 'Madrugar')]),
        nueve,
      );
      expect(d.vacio, isFalse);
      expect(d.proximo, isNull);
      expect(d.hoy, isEmpty);
      expect(d.sinPendientes, isTrue);
    });
  });

  group('hoy (lista capada + overflow)', () {
    test('muestra actual + próximos desde ahora, en orden', () {
      final d = construirDatosWidget(
        _plan([
          _b(inicio: '07:00', fin: '08:00', titulo: 'Pasado'), // ya terminó
          _b(inicio: '08:30', fin: '10:00', titulo: 'Ahora'),
          _b(inicio: '11:00', fin: '12:00', titulo: 'Luego'),
        ]),
        nueve,
      );
      expect(d.hoy.map((e) => e.titulo).toList(), ['Ahora', 'Luego']);
      expect(d.overflow, 0);
    });

    test('capa a maxHoy y reporta +X más', () {
      final bloques = [
        for (var h = 10; h < 18; h++)
          _b(inicio: '$h:00', fin: '$h:30', titulo: 'B$h'),
      ];
      final d = construirDatosWidget(_plan(bloques), nueve, maxHoy: 4);
      expect(d.hoy.length, 4);
      expect(d.overflow, 4); // 8 relevantes - 4 mostrados
    });
  });

  group('colorWidget (semántica de barra por ítem)', () {
    test('proyecto/trabajo → azul; práctica tentativa → ámbar', () {
      expect(colorWidget('trabajo', false), '#2D7FF9'); // proyecto azul
      expect(colorWidget('tarea', false), '#2D7FF9'); // tarea tentativa azul
      expect(colorWidget('skill', false), '#E0A33A'); // práctica ámbar
    });
    test('evento fijo → verde; vencido → rojo', () {
      expect(colorWidget('clase', true), '#21D07A'); // fijo verde
      expect(colorWidget('evento', true), '#21D07A');
      expect(colorWidget('tarea', false, vencido: true), '#FF4D5E'); // rojo
    });
  });

  group('fechaCorta', () {
    test('formatea en español sin init de locale', () {
      expect(fechaCorta(DateTime(2026, 6, 8)), 'lun 8 jun'); // lunes
      expect(fechaCorta(DateTime(2026, 12, 25)), 'vie 25 dic'); // viernes
    });
  });
}
