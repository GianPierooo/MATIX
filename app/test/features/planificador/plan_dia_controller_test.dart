import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:matix/features/eventos/domain/evento.dart';
import 'package:matix/features/eventos/providers/eventos_providers.dart';
import 'package:matix/features/planificador/application/plan_dia_controller.dart';
import 'package:matix/features/planificador/data/duraciones_repository.dart';
import 'package:matix/features/tareas/data/tareas_repository.dart';
import 'package:matix/features/tareas/domain/tarea.dart';
import 'package:matix/features/tareas/providers/tareas_providers.dart';

/// Test del flujo del controlador: que ACEPTAR cree los bloques
/// (cada tarea aceptada se guarda con bloque_inicio/bloque_fin vía el
/// repo). Inyectamos `ahora` para que el encaje sea determinístico y
/// usamos fakes para no tocar red.

class _FakeDuraciones implements DuracionesRepository {
  @override
  Future<Map<String, int>> estimar(List<Tarea> tareas) async => const {};
}

class _FakeTareasRepo implements TareasRepository {
  final List<Map<String, dynamic>> actualizadas = [];

  @override
  Future<Tarea> actualizar(String id, Map<String, dynamic> cambios) async {
    actualizadas.add({'id': id, ...cambios});
    final base = DateTime(2026, 1, 1);
    return Tarea(id: id, titulo: id, creadaEn: base, actualizadaEn: base);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Tarea _t(String id) {
  final base = DateTime(2026, 1, 1);
  return Tarea(id: id, titulo: 'Tarea $id', creadaEn: base, actualizadaEn: base);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('planificar + aceptar crea un bloque por tarea', () async {
    SharedPreferences.setMockInitialValues({}); // ventana 9–21, silencio 22–8
    final fakeRepo = _FakeTareasRepo();

    final c = ProviderContainer(overrides: [
      tareasProvider.overrideWith((ref) async => [_t('a'), _t('b')]),
      eventosProvider.overrideWith((ref) async => <Evento>[]),
      duracionesRepositoryProvider.overrideWithValue(_FakeDuraciones()),
      tareasRepositoryProvider.overrideWithValue(fakeRepo),
    ]);
    addTearDown(c.dispose);

    final ctrl = c.read(planDiaControllerProvider.notifier);
    // Mañana, dentro de la ventana: hay huecos para ambas tareas.
    await ctrl.planificar(ahora: DateTime(2026, 6, 10, 9, 0));

    var estado = c.read(planDiaControllerProvider);
    expect(estado.fase, FasePlan.revision);
    expect(estado.plan!.bloques.length, 2);

    await ctrl.aplicar();

    estado = c.read(planDiaControllerProvider);
    expect(estado.fase, FasePlan.aplicado);
    expect(estado.aplicados, 2);
    // Cada tarea quedó con su bloque (inicio/fin).
    expect(fakeRepo.actualizadas.length, 2);
    for (final cambio in fakeRepo.actualizadas) {
      expect(cambio.containsKey('bloque_inicio'), isTrue);
      expect(cambio.containsKey('bloque_fin'), isTrue);
    }
  });

  test('quitar saca la tarea del plan', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer(overrides: [
      tareasProvider.overrideWith((ref) async => [_t('a'), _t('b')]),
      eventosProvider.overrideWith((ref) async => <Evento>[]),
      duracionesRepositoryProvider.overrideWithValue(_FakeDuraciones()),
      tareasRepositoryProvider.overrideWithValue(_FakeTareasRepo()),
    ]);
    addTearDown(c.dispose);

    final ctrl = c.read(planDiaControllerProvider.notifier);
    await ctrl.planificar(ahora: DateTime(2026, 6, 10, 9, 0));
    expect(c.read(planDiaControllerProvider).plan!.bloques.length, 2);

    ctrl.quitar('a');
    final plan = c.read(planDiaControllerProvider).plan!;
    expect(plan.bloques.length, 1);
    expect(plan.bloques.first.tareaId, 'b');
  });
}
