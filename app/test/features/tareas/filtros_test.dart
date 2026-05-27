import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/tareas/domain/tarea.dart';
import 'package:matix/features/tareas/providers/tareas_providers.dart';

/// Tests de la lógica pura de `tareasFiltradasProvider`: aplicar vista
/// + filtros sobre una lista cruda. No tocan red — se sobreescribe el
/// `tareasProvider` con datos dummy.

Tarea _tarea({
  required String id,
  DateTime? venceEn,
  bool completada = false,
  Prioridad prioridad = Prioridad.media,
  String? cursoId,
  String? categoriaId,
  String? proyectoId,
}) {
  final ahora = DateTime.now();
  return Tarea(
    id: id,
    titulo: 't_$id',
    venceEn: venceEn,
    prioridad: prioridad,
    completada: completada,
    cursoId: cursoId,
    categoriaId: categoriaId,
    proyectoId: proyectoId,
    creadaEn: ahora,
    actualizadaEn: ahora,
  );
}

ProviderContainer _contenedor(List<Tarea> tareas) {
  final c = ProviderContainer(overrides: [
    tareasProvider.overrideWith((_) async => tareas),
  ]);
  return c;
}

void main() {
  group('tareasFiltradasProvider', () {
    test('vista=hoy deja solo las que vencen hoy y no están completadas',
        () async {
      // Usar las 12:00 del día actual evita falsos negativos a la
      // medianoche (ahora+2h podría caer en el día siguiente).
      final ahora = DateTime.now();
      final hoy = DateTime(ahora.year, ahora.month, ahora.day, 12, 0);
      final manana = hoy.add(const Duration(days: 1));
      final tareas = [
        _tarea(id: '1', venceEn: hoy),
        _tarea(id: '2', venceEn: manana),
        _tarea(id: '3', venceEn: hoy, completada: true),
        _tarea(id: '4'), // sin fecha
      ];
      final c = _contenedor(tareas);
      addTearDown(c.dispose);
      await c.read(tareasProvider.future);
      c.read(vistaTareasProvider.notifier).set(VistaTareas.hoy);

      final out = c.read(tareasFiltradasProvider).value!;
      expect(out.map((t) => t.id), ['1']);
    });

    test('vista=todas excluye completadas', () async {
      final tareas = [
        _tarea(id: 'a'),
        _tarea(id: 'b', completada: true),
        _tarea(id: 'c'),
      ];
      final c = _contenedor(tareas);
      addTearDown(c.dispose);
      await c.read(tareasProvider.future);
      c.read(vistaTareasProvider.notifier).set(VistaTareas.todas);

      final out = c.read(tareasFiltradasProvider).value!;
      expect(out.map((t) => t.id).toSet(), {'a', 'c'});
    });

    test('vista=completadas deja solo las completadas', () async {
      final tareas = [
        _tarea(id: 'a'),
        _tarea(id: 'b', completada: true),
        _tarea(id: 'c', completada: true),
      ];
      final c = _contenedor(tareas);
      addTearDown(c.dispose);
      await c.read(tareasProvider.future);
      c.read(vistaTareasProvider.notifier).set(VistaTareas.completadas);

      final out = c.read(tareasFiltradasProvider).value!;
      expect(out.map((t) => t.id).toSet(), {'b', 'c'});
    });

    test('filtro por prioridad solo deja la prioridad indicada',
        () async {
      final tareas = [
        _tarea(id: 'a', prioridad: Prioridad.alta),
        _tarea(id: 'b', prioridad: Prioridad.media),
        _tarea(id: 'c', prioridad: Prioridad.baja),
      ];
      final c = _contenedor(tareas);
      addTearDown(c.dispose);
      await c.read(tareasProvider.future);
      c.read(vistaTareasProvider.notifier).set(VistaTareas.todas);
      c.read(filtrosTareasProvider.notifier).set(
            const FiltrosTareas(prioridad: Prioridad.alta),
          );

      final out = c.read(tareasFiltradasProvider).value!;
      expect(out.map((t) => t.id), ['a']);
    });

    test('filtro por proyecto solo deja las del proyecto pedido',
        () async {
      final tareas = [
        _tarea(id: 'a', proyectoId: 'matix'),
        _tarea(id: 'b', proyectoId: 'onexotic'),
        _tarea(id: 'c'),
      ];
      final c = _contenedor(tareas);
      addTearDown(c.dispose);
      await c.read(tareasProvider.future);
      c.read(vistaTareasProvider.notifier).set(VistaTareas.todas);
      c.read(filtrosTareasProvider.notifier)
          .set(const FiltrosTareas(proyectoId: 'matix'));

      final out = c.read(tareasFiltradasProvider).value!;
      expect(out.map((t) => t.id), ['a']);
    });

    test('vencidas aparecen primero', () async {
      final ahora = DateTime.now();
      final ayer = ahora.subtract(const Duration(days: 1));
      final manana = ahora.add(const Duration(days: 1));
      final tareas = [
        _tarea(id: 'futuro', venceEn: manana),
        _tarea(id: 'vencida', venceEn: ayer),
      ];
      final c = _contenedor(tareas);
      addTearDown(c.dispose);
      await c.read(tareasProvider.future);
      c.read(vistaTareasProvider.notifier).set(VistaTareas.todas);

      final out = c.read(tareasFiltradasProvider).value!;
      expect(out.first.id, 'vencida');
    });

    test('limpiar() borra todos los filtros', () {
      final c = _contenedor([]);
      addTearDown(c.dispose);
      c.read(filtrosTareasProvider.notifier).set(const FiltrosTareas(
            prioridad: Prioridad.alta,
            venceEnDias: 3,
          ));
      expect(c.read(filtrosTareasProvider).activos, 2);

      c.read(filtrosTareasProvider.notifier).limpiar();
      expect(c.read(filtrosTareasProvider).vacio, isTrue);
    });
  });
}
