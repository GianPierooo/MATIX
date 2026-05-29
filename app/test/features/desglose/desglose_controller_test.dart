import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matix/features/desglose/application/desglose_controller.dart';
import 'package:matix/features/desglose/data/desglose_repository.dart';
import 'package:matix/features/desglose/domain/paso_propuesto.dart';
import 'package:matix/features/tareas/data/tareas_repository.dart';
import 'package:matix/features/tareas/domain/tarea.dart';
import 'package:matix/features/tareas/providers/tareas_providers.dart';

/// Tests del desglose (Capa 7): que una tarea atómica no se infle, que
/// aceptar cree los pasos en el proyecto correcto, y las ediciones.
/// El parseo del JSON se prueba aparte con `PasoPropuesto.fromCerebro`.

class _FakeDesglose implements DesgloseRepository {
  _FakeDesglose(this.resultado);
  final ResultadoDesglose resultado;
  @override
  Future<ResultadoDesglose> desglosar({
    required String titulo,
    String? nota,
  }) async =>
      resultado;
}

class _FakeTareas implements TareasRepository {
  final List<Map<String, dynamic>> creadas = [];

  @override
  Future<Tarea> crear({
    required String titulo,
    String? nota,
    DateTime? venceEn,
    Prioridad prioridad = Prioridad.media,
    String? categoriaId,
    String? cursoId,
    String? proyectoId,
    Repeticion? repeticion,
    DateTime? recordarEn,
  }) async {
    creadas.add({
      'titulo': titulo,
      'prioridad': prioridad,
      'proyectoId': proyectoId,
      'cursoId': cursoId,
    });
    final base = DateTime(2026, 1, 1);
    return Tarea(
      id: 't${creadas.length}',
      titulo: titulo,
      prioridad: prioridad,
      proyectoId: proyectoId,
      cursoId: cursoId,
      creadaEn: base,
      actualizadaEn: base,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

ProviderContainer _contenedor({
  required DesgloseRepository desglose,
  TareasRepository? tareas,
}) {
  final c = ProviderContainer(overrides: [
    desgloseRepositoryProvider.overrideWithValue(desglose),
    if (tareas != null) tareasRepositoryProvider.overrideWithValue(tareas),
  ]);
  addTearDown(c.dispose);
  return c;
}

DesgloseController _ctrl(ProviderContainer c) =>
    c.read(desgloseControllerProvider.notifier);

void main() {
  group('PasoPropuesto.fromCerebro (parseo JSON)', () {
    test('parsea título y horizonte', () {
      final p = PasoPropuesto.fromCerebro(
          {'titulo': '  Elegir tema  ', 'horizonte': 'ahora'});
      expect(p.titulo, 'Elegir tema');
      expect(p.horizonte, Horizonte.ahora);
    });
    test('horizonte desconocido cae en pronto', () {
      final p = PasoPropuesto.fromCerebro({'titulo': 'X', 'horizonte': 'xyz'});
      expect(p.horizonte, Horizonte.pronto);
    });
    test('mas_adelante mapea a prioridad baja; ahora a alta', () {
      expect(Horizonte.masAdelante.prioridad, Prioridad.baja);
      expect(Horizonte.ahora.prioridad, Prioridad.alta);
      expect(Horizonte.pronto.prioridad, Prioridad.media);
    });
  });

  test('tarea atómica → no se infla (revision, esAtomica, sin pasos)',
      () async {
    final c = _contenedor(
      desglose:
          _FakeDesglose(const ResultadoDesglose(esAtomica: true, pasos: [])),
    );
    await _ctrl(c).desglosar(titulo: 'Comprar pan');
    final estado = c.read(desgloseControllerProvider);
    expect(estado.fase, FaseDesglose.revision);
    expect(estado.esAtomica, isTrue);
    expect(estado.pasos, isEmpty);
  });

  test('aceptar crea los pasos en el proyecto/curso de la original',
      () async {
    final fakeTareas = _FakeTareas();
    final c = _contenedor(
      desglose: _FakeDesglose(ResultadoDesglose(esAtomica: false, pasos: [
        PasoPropuesto(titulo: 'Elegir tema', horizonte: Horizonte.ahora),
        PasoPropuesto(titulo: 'Leer fuentes', horizonte: Horizonte.pronto),
      ])),
      tareas: fakeTareas,
    );
    await _ctrl(c)
        .desglosar(titulo: 'Hacer la tesis', proyectoId: 'p1', cursoId: 'c1');

    await _ctrl(c).crear();

    final estado = c.read(desgloseControllerProvider);
    expect(estado.fase, FaseDesglose.creado);
    expect(estado.creados, 2);
    expect(fakeTareas.creadas, hasLength(2));
    // Heredan proyecto y curso de la original.
    expect(fakeTareas.creadas.every((t) => t['proyectoId'] == 'p1'), isTrue);
    expect(fakeTareas.creadas.every((t) => t['cursoId'] == 'c1'), isTrue);
    // El horizonte viaja como prioridad.
    expect(fakeTareas.creadas[0]['prioridad'], Prioridad.alta);
    expect(fakeTareas.creadas[1]['prioridad'], Prioridad.media);
  });

  test('ediciones: título, horizonte, quitar, reordenar', () async {
    final c = _contenedor(
      desglose: _FakeDesglose(ResultadoDesglose(esAtomica: false, pasos: [
        PasoPropuesto(titulo: 'A'),
        PasoPropuesto(titulo: 'B'),
        PasoPropuesto(titulo: 'C'),
      ])),
    );
    await _ctrl(c).desglosar(titulo: 'algo');

    _ctrl(c).editarTitulo(0, 'A corregido');
    _ctrl(c).cambiarHorizonte(1, Horizonte.ahora);
    _ctrl(c).reordenar(2, 0); // C al frente

    var e = c.read(desgloseControllerProvider);
    expect(e.pasos.map((p) => p.titulo), ['C', 'A corregido', 'B']);
    expect(e.pasos[2].horizonte, Horizonte.ahora);

    _ctrl(c).quitar(0); // quita C
    e = c.read(desgloseControllerProvider);
    expect(e.pasos.map((p) => p.titulo), ['A corregido', 'B']);
  });

  test('reiniciar vuelve a inicial', () async {
    final c = _contenedor(
      desglose: _FakeDesglose(ResultadoDesglose(
          esAtomica: false, pasos: [PasoPropuesto(titulo: 'X')])),
    );
    await _ctrl(c).desglosar(titulo: 'algo');
    expect(c.read(desgloseControllerProvider).fase, FaseDesglose.revision);
    _ctrl(c).reiniciar();
    expect(c.read(desgloseControllerProvider).fase, FaseDesglose.inicial);
  });
}
