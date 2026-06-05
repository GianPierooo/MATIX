import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/horario/domain/plan_dia.dart';
import 'package:matix/features/mascota/domain/personalidad.dart';
import 'package:matix/features/mascota/domain/presencia.dart';

BloquePlan _bloque({
  required String inicio,
  required String fin,
  String titulo = 'Bloque',
  String tipo = 'trabajo',
  bool tentativo = true,
  String? proyecto,
  String? tareaId,
  String? setItemId,
}) =>
    BloquePlan(
      inicio: inicio,
      fin: fin,
      titulo: titulo,
      tipo: tipo,
      tentativo: tentativo,
      proyecto: proyecto,
      tareaId: tareaId,
      setItemId: setItemId,
    );

PlanDia _plan(List<BloquePlan> bloques, {List<Sugerencia> sug = const []}) =>
    PlanDia(
      fecha: '2026-06-04',
      despierta: '07:00',
      duerme: '23:00',
      bloques: bloques,
      fuera: const [],
      sugerencias: sug,
    );

void main() {
  final nueve = DateTime(2026, 6, 4, 9); // 09:00 → 540 min, mañana

  group('bloqueActual / bloqueSiguiente', () {
    final bs = [
      _bloque(inicio: '08:30', fin: '10:00'),
      _bloque(inicio: '11:00', fin: '12:00'),
    ];
    test('actual cubre la hora; siguiente es el más cercano por delante', () {
      expect(bloqueActual(bs, 540)?.inicio, '08:30');
      expect(bloqueActual(bs, 630), isNull); // 10:30, en el hueco
      expect(bloqueSiguiente(bs, 630)?.inicio, '11:00');
      expect(bloqueSiguiente(bs, 720), isNull); // 12:00, ya no hay más
    });
  });

  group('mensajePresencia', () {
    test('bloque tentativo en curso → accionable (Hecho) con su id', () {
      final plan = _plan([
        _bloque(
          inicio: '08:30',
          fin: '10:00',
          titulo: 'OneXotic: landing',
          proyecto: 'OneXotic',
          tareaId: 't1',
          setItemId: 's1',
        ),
      ]);
      final m = mensajePresencia(plan, ContextoMascota.vacio, nueve);
      expect(m.tipo, TipoPresencia.ahora);
      expect(m.acciones.first, AccionPresencia.hecho);
      expect(m.tareaId, 't1');
      expect(m.texto, contains('OneXotic: landing'));
      expect(m.texto.contains('*'), isFalse);
    });

    test('rato libre con sugerencia del plan', () {
      final plan = _plan(
        [_bloque(inicio: '11:00', fin: '12:00', titulo: 'Clase', tipo: 'clase', tentativo: false)],
        sug: const [Sugerencia(titulo: 'Práctica: Inglés', tipo: 'skill', durMin: 30)],
      );
      final m = mensajePresencia(plan, ContextoMascota.vacio, nueve);
      expect(m.tipo, TipoPresencia.libre);
      expect(m.texto, contains('Inglés'));
      expect(m.texto, contains('2h')); // 09:00 → 11:00 libre
    });

    test('lo que sigue, si está cerca', () {
      final plan = _plan([_bloque(inicio: '09:30', fin: '10:00', titulo: 'Gym', tipo: 'evento', tentativo: false)]);
      final m = mensajePresencia(plan, ContextoMascota.vacio, nueve);
      expect(m.tipo, TipoPresencia.siguiente);
      expect(m.texto, contains('Gym'));
      expect(m.texto, contains('30min'));
    });

    test('sin plan: atrasos sin culpa', () {
      final m = mensajePresencia(null, const ContextoMascota(vencidas: 2), nueve);
      expect(m.tipo, TipoPresencia.pendientes);
      expect(m.texto, contains('2'));
      expect(m.texto.toLowerCase(), isNot(contains('deberías')));
    });

    test('sin nada relevante: idle por franja, con acciones', () {
      final m = mensajePresencia(null, ContextoMascota.vacio, nueve);
      expect(m.tipo, TipoPresencia.idle);
      expect(m.texto, isNotEmpty);
      expect(m.acciones, isNotEmpty);
      expect(m.texto.contains('*'), isFalse);
    });
  });

  group('felicitacionPresencia', () {
    test('celebra con el conteo y sin asteriscos', () {
      final m = felicitacionPresencia(const ContextoMascota(hechasHoy: 3));
      expect(m.tipo, TipoPresencia.felicitacion);
      expect(m.texto, contains('3'));
      expect(m.acciones, contains(AccionPresencia.seguimos));
      expect(m.texto.contains('*'), isFalse);
    });
  });

  group('poolPresencia (variedad ambiental)', () {
    test('nunca vacío y sin asteriscos en ninguna frase', () {
      final pool = poolPresencia(null, ContextoMascota.vacio, nueve);
      expect(pool, isNotEmpty);
      for (final m in pool) {
        expect(m.texto, isNotEmpty);
        expect(m.texto.contains('*'), isFalse);
      }
    });

    test('incluye siempre aliento, dato y un idle por franja', () {
      // Sin plan ni señales: el pool es puramente ambiental, con varias
      // opciones para rotar (no una sola repetida).
      final pool = poolPresencia(null, ContextoMascota.vacio, nueve);
      expect(pool.length, greaterThanOrEqualTo(3));
    });

    test('atraso ofrece reprogramar (esto venció, ¿lo muevo?)', () {
      final pool = poolPresencia(null, const ContextoMascota(vencidas: 1), nueve);
      final venc = pool.firstWhere(
          (m) => m.acciones.contains(AccionPresencia.reprogramar));
      expect(venc.texto, contains('1'));
      expect(venc.texto.contains('*'), isFalse);
    });

    test('proyecto sin acción siguiente aparece en el pool', () {
      final pool = poolPresencia(
        null,
        const ContextoMascota(
            proyectosActivos: 1, proyectoSinSiguiente: 'OneXotic'),
        nueve,
      );
      expect(pool.any((m) => m.texto.contains('OneXotic')), isTrue);
    });

    test('backlog: surfacea las tareas sin fecha (no mueren calladas)', () {
      final pool = poolPresencia(
        null, const ContextoMascota(tareasSinFecha: 3), nueve);
      final backlog = pool.firstWhere(
          (m) => m.texto.contains('sin fecha') || m.texto.contains('sin fecha sueltas'),
          orElse: () => pool.firstWhere((m) => m.texto.contains('3')));
      expect(backlog.texto, contains('3'));
      expect(backlog.texto.contains('*'), isFalse);
    });

    test('sin backlog no aparece la sugerencia de sin fecha', () {
      final pool = poolPresencia(null, ContextoMascota.vacio, nueve);
      expect(pool.any((m) => m.texto.contains('sin fecha')), isFalse);
    });
  });

  group('mensajePresencia con rotación', () {
    test('rotación recorre el pool (cambia de mensaje)', () {
      const ctx = ContextoMascota(vencidas: 1, tareasHoy: 2);
      final textos = <String>{
        for (var r = 0; r < 6; r++)
          mensajePresencia(null, ctx, nueve, rotacion: r).texto,
      };
      // Con varios candidatos relevantes, la rotación produce variedad real.
      expect(textos.length, greaterThan(1));
    });

    test('rotación 0 sigue dando el más relevante (compatibilidad)', () {
      final plan = _plan([
        _bloque(
          inicio: '08:30',
          fin: '10:00',
          titulo: 'OneXotic: landing',
          tareaId: 't1',
          setItemId: 's1',
        ),
      ]);
      final m = mensajePresencia(plan, ContextoMascota.vacio, nueve);
      expect(m.tipo, TipoPresencia.ahora);
      expect(m.acciones.first, AccionPresencia.hecho);
    });
  });

  group('accionableActual', () {
    test('encuentra el bloque accionable de ahora', () {
      final plan = _plan([
        _bloque(
          inicio: '08:30',
          fin: '10:00',
          titulo: 'OneXotic: landing',
          tareaId: 't1',
          setItemId: 's1',
        ),
      ]);
      final m = accionableActual(plan, ContextoMascota.vacio, nueve);
      expect(m, isNotNull);
      expect(m!.tareaId, 't1');
    });

    test('sin nada accionable → null', () {
      final m = accionableActual(null, ContextoMascota.vacio, nueve);
      expect(m, isNull);
    });
  });
}
