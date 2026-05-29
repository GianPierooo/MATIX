import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/apuntes/domain/apunte.dart';
import 'package:matix/features/cursos/domain/curso.dart';
import 'package:matix/features/cursos/domain/sesion_clase.dart';
import 'package:matix/features/evaluaciones/domain/evaluacion.dart';
import 'package:matix/features/tareas/domain/tarea.dart';
import 'package:matix/screens/inicio_screen.dart';

/// Tests de la lógica pura del tablero de Inicio: qué tareas entran al
/// bloque "Hoy", qué apuntes son los recientes, y cuál es el próximo
/// ítem de Universidad. Sin red ni widgets: solo funciones puras.

Tarea _tarea({
  required String id,
  DateTime? venceEn,
  bool completada = false,
}) {
  final base = DateTime(2026, 1, 1);
  return Tarea(
    id: id,
    titulo: id,
    venceEn: venceEn,
    completada: completada,
    creadaEn: base,
    actualizadaEn: base,
  );
}

Apunte _apunte(String id, DateTime actualizado) => Apunte(
      id: id,
      titulo: id,
      creadoEn: actualizado,
      actualizadoEn: actualizado,
    );

Curso _curso(String id, String nombre) {
  final base = DateTime(2026, 1, 1);
  return Curso(id: id, nombre: nombre, creadoEn: base, actualizadoEn: base);
}

SesionClase _sesion({
  required String id,
  required String cursoId,
  required int diaSemana,
  required String horaInicio,
}) =>
    SesionClase(
      id: id,
      cursoId: cursoId,
      diaSemana: diaSemana,
      horaInicio: horaInicio,
      horaFin: '23:59:00',
    );

Evaluacion _evaluacion({
  required String id,
  required String cursoId,
  required DateTime fecha,
  double? nota,
  TipoEvaluacion tipo = TipoEvaluacion.entrega,
}) {
  final base = DateTime(2026, 1, 1);
  return Evaluacion(
    id: id,
    cursoId: cursoId,
    titulo: id,
    tipo: tipo,
    fecha: fecha,
    notaObtenida: nota,
    creadaEn: base,
    actualizadaEn: base,
  );
}

void main() {
  group('tareasDeHoy', () {
    final ahora = DateTime(2026, 5, 28, 12, 0);

    test('incluye vencidas y las de hoy; vencidas primero', () {
      final vencidaAyer = _tarea(
        id: 'vencida',
        venceEn: DateTime(2026, 5, 27, 9, 0),
      );
      final hoyTarde = _tarea(
        id: 'hoy',
        venceEn: DateTime(2026, 5, 28, 15, 0),
      );
      final manana = _tarea(
        id: 'manana',
        venceEn: DateTime(2026, 5, 29, 9, 0),
      );
      final completada = _tarea(
        id: 'completada',
        venceEn: DateTime(2026, 5, 28, 10, 0),
        completada: true,
      );
      final sinFecha = _tarea(id: 'sinFecha');

      final out = tareasDeHoy(
        [hoyTarde, manana, completada, sinFecha, vencidaAyer],
        ahora,
      );

      expect(out.map((t) => t.id), ['vencida', 'hoy']);
    });

    test('entre dos vencidas, la más antigua va primero', () {
      final a = _tarea(id: 'a', venceEn: DateTime(2026, 5, 27, 9, 0));
      final b = _tarea(id: 'b', venceEn: DateTime(2026, 5, 26, 9, 0));

      final out = tareasDeHoy([a, b], ahora);

      expect(out.map((t) => t.id), ['b', 'a']);
    });

    test('lista vacía → vacío', () {
      expect(tareasDeHoy([], ahora), isEmpty);
    });
  });

  group('apuntesRecientes', () {
    test('ordena por actualizadoEn descendente y corta en max', () {
      final apuntes = [
        _apunte('1', DateTime(2026, 5, 1)),
        _apunte('2', DateTime(2026, 5, 10)),
        _apunte('3', DateTime(2026, 5, 5)),
        _apunte('4', DateTime(2026, 5, 28)),
        _apunte('5', DateTime(2026, 5, 20)),
        _apunte('6', DateTime(2026, 5, 15)),
        _apunte('7', DateTime(2026, 4, 1)),
      ];

      final out = apuntesRecientes(apuntes);

      expect(out.length, 5);
      expect(out.map((a) => a.id), ['4', '5', '6', '2', '3']);
    });

    test('respeta un max personalizado', () {
      final apuntes = [
        _apunte('1', DateTime(2026, 5, 1)),
        _apunte('2', DateTime(2026, 5, 2)),
        _apunte('3', DateTime(2026, 5, 3)),
      ];

      final out = apuntesRecientes(apuntes, max: 2);

      expect(out.map((a) => a.id), ['3', '2']);
    });

    test('no muta la lista original', () {
      final apuntes = [
        _apunte('1', DateTime(2026, 5, 1)),
        _apunte('2', DateTime(2026, 5, 2)),
      ];

      apuntesRecientes(apuntes);

      expect(apuntes.map((a) => a.id), ['1', '2']);
    });
  });

  group('proximoUni', () {
    final ahora = DateTime(2026, 5, 28, 12, 0);
    final cursos = [_curso('c1', 'Cálculo')];

    test('sin nada → null', () {
      expect(proximoUni([], cursos, [], ahora), isNull);
    });

    test('toma la próxima entrega futura sin nota', () {
      final eval = [
        _evaluacion(
          id: 'e1',
          cursoId: 'c1',
          fecha: DateTime(2026, 5, 30, 9, 0),
        ),
        _evaluacion(
          id: 'e2',
          cursoId: 'c1',
          fecha: DateTime(2026, 6, 5, 9, 0),
        ),
      ];

      final out = proximoUni([], cursos, eval, ahora);

      expect(out, isNotNull);
      expect(out!.titulo, 'e1');
      expect(out.esClase, isFalse);
      expect(out.cursoNombre, 'Cálculo');
      expect(out.tipoLabel, 'Entrega');
    });

    test('ignora entregas con nota y entregas pasadas', () {
      final eval = [
        _evaluacion(
          id: 'conNota',
          cursoId: 'c1',
          fecha: DateTime(2026, 5, 30, 9, 0),
          nota: 18,
        ),
        _evaluacion(
          id: 'pasada',
          cursoId: 'c1',
          fecha: DateTime(2026, 5, 20, 9, 0),
        ),
        _evaluacion(
          id: 'futura',
          cursoId: 'c1',
          fecha: DateTime(2026, 6, 1, 9, 0),
        ),
      ];

      final out = proximoUni([], cursos, eval, ahora);

      expect(out!.titulo, 'futura');
    });

    test('elige la clase cuando ocurre antes que la entrega', () {
      final hoy = ahora.weekday - 1;
      final sesiones = [
        _sesion(id: 's1', cursoId: 'c1', diaSemana: hoy, horaInicio: '15:00:00'),
      ];
      final eval = [
        _evaluacion(
          id: 'e1',
          cursoId: 'c1',
          fecha: DateTime(2026, 6, 1, 9, 0),
        ),
      ];

      final out = proximoUni(sesiones, cursos, eval, ahora);

      expect(out!.esClase, isTrue);
      expect(out.cuando, DateTime(2026, 5, 28, 15, 0));
    });

    test('salta una clase que ya empezó hoy y toma la de la semana próxima',
        () {
      final hoy = ahora.weekday - 1;
      final sesiones = [
        // 08:00 < ahora (12:00) → hoy ya pasó; debe ir a +7 días.
        _sesion(id: 's1', cursoId: 'c1', diaSemana: hoy, horaInicio: '08:00:00'),
      ];

      final out = proximoUni(sesiones, cursos, [], ahora);

      expect(out!.esClase, isTrue);
      expect(out.cuando, DateTime(2026, 6, 4, 8, 0));
    });
  });

  group('ideasParaReflotar', () {
    final ahora = DateTime(2026, 5, 28, 12, 0);

    test('incluye apuntes generales viejos (14+ días) y excluye recientes',
        () {
      final vieja = _idea('vieja', DateTime(2026, 5, 1)); // 27 días
      final justo = _idea('justo', DateTime(2026, 5, 14)); // 14 días exactos
      final reciente = _idea('reciente', DateTime(2026, 5, 20)); // 8 días

      final out = ideasParaReflotar([reciente, vieja, justo], ahora);

      // Solo las que pasan el umbral de 14 días; más viejas primero.
      expect(out.map((a) => a.id), ['vieja', 'justo']);
    });

    test('excluye archivadas (no vuelven nunca)', () {
      final archivada = _idea('arch', DateTime(2026, 5, 1),
          archivadoEn: DateTime(2026, 5, 10));
      final viva = _idea('viva', DateTime(2026, 5, 1));

      final out = ideasParaReflotar([archivada, viva], ahora);

      expect(out.map((a) => a.id), ['viva']);
    });

    test('retomar (tocar) la saca: una actualizada hoy no es candidata', () {
      final dormida = _idea('dormida', DateTime(2026, 5, 1));
      // Tras "retomar", el cerebro bumpea actualizadoEn a ahora.
      final retomada = _idea('retomada', ahora);

      final out = ideasParaReflotar([dormida, retomada], ahora);

      expect(out.map((a) => a.id), ['dormida']);
    });

    test('solo apuntes generales: excluye los de proyecto/curso/cuaderno', () {
      final general = _idea('general', DateTime(2026, 5, 1));
      final deProyecto =
          _idea('proj', DateTime(2026, 5, 1), proyectoId: 'p1');
      final deCurso = _idea('curso', DateTime(2026, 5, 1), cursoId: 'c1');
      final deCuaderno =
          _idea('cuad', DateTime(2026, 5, 1), cuadernoId: 'q1');

      final out = ideasParaReflotar(
        [general, deProyecto, deCurso, deCuaderno],
        ahora,
      );

      expect(out.map((a) => a.id), ['general']);
    });

    test('corta en max y muestra las más viejas primero', () {
      final ideas = [
        _idea('a', DateTime(2026, 5, 1)),
        _idea('b', DateTime(2026, 4, 1)),
        _idea('c', DateTime(2026, 3, 1)),
        _idea('d', DateTime(2026, 2, 1)),
      ];

      final out = ideasParaReflotar(ideas, ahora, max: 2);

      // Las dos más viejas: 'd' (feb) y 'c' (mar).
      expect(out.map((a) => a.id), ['d', 'c']);
    });

    test('lista vacía → vacío', () {
      expect(ideasParaReflotar([], ahora), isEmpty);
    });
  });
}

Apunte _idea(
  String id,
  DateTime actualizado, {
  DateTime? archivadoEn,
  String? proyectoId,
  String? cursoId,
  String? cuadernoId,
}) =>
    Apunte(
      id: id,
      titulo: id,
      creadoEn: actualizado,
      actualizadoEn: actualizado,
      archivadoEn: archivadoEn,
      proyectoId: proyectoId,
      cursoId: cursoId,
      cuadernoId: cuadernoId,
    );
