import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matix/api/matix_client.dart';
import 'package:matix/features/captura_camara/application/extraccion_tareas_controller.dart';
import 'package:matix/features/captura_camara/data/extraccion_tareas_repository.dart';
import 'package:matix/features/captura_camara/domain/tarea_propuesta.dart';
import 'package:matix/features/tareas/data/tareas_repository.dart';
import 'package:matix/features/tareas/domain/tarea.dart';
import 'package:matix/features/tareas/providers/tareas_providers.dart';

/// Tests del `ExtraccionTareasController` (Capa 7-B). No tocamos red:
/// sustituimos el repo que llama al cerebro y el repo de tareas por
/// fakes. El de extracción implementa su única interfaz; el de tareas
/// usa `noSuchMethod` porque el controller solo invoca `crear`.

class _FakeExtraccion implements ExtraccionTareasRepository {
  _FakeExtraccion({this.resultado = const [], this.error});
  final List<TareaPropuesta> resultado;
  final Object? error;

  @override
  Future<List<TareaPropuesta>> extraer(String texto) async {
    if (error != null) throw error!;
    return resultado;
  }
}

class _FakeTareas implements TareasRepository {
  _FakeTareas({this.fallaEnLlamada});

  /// Si no es null, la N-ésima llamada a `crear` (1-based) lanza.
  final int? fallaEnLlamada;
  final List<Map<String, dynamic>> creadas = [];
  int _llamadas = 0;

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
    _llamadas++;
    if (fallaEnLlamada != null && _llamadas == fallaEnLlamada) {
      throw MatixApiException(500, 'fallo de red');
    }
    creadas.add({
      'titulo': titulo,
      'venceEn': venceEn,
      'proyectoId': proyectoId,
    });
    return Tarea(
      id: 't$_llamadas',
      titulo: titulo,
      venceEn: venceEn,
      proyectoId: proyectoId,
      creadaEn: DateTime.now(),
      actualizadaEn: DateTime.now(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

ProviderContainer _contenedor({
  required ExtraccionTareasRepository extraccion,
  TareasRepository? tareas,
}) {
  final c = ProviderContainer(
    overrides: [
      extraccionTareasRepositoryProvider.overrideWithValue(extraccion),
      if (tareas != null)
        tareasRepositoryProvider.overrideWithValue(tareas),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

ExtraccionTareasController _ctrl(ProviderContainer c) =>
    c.read(extraccionTareasControllerProvider.notifier);

void main() {
  test('estado inicial es fase inicial, sin propuestas', () {
    final c = _contenedor(extraccion: _FakeExtraccion());
    final estado = c.read(extraccionTareasControllerProvider);
    expect(estado.fase, FaseExtraccion.inicial);
    expect(estado.propuestas, isEmpty);
    expect(estado.error, isNull);
  });

  test('interpretar con tareas → revisión con propuestas', () async {
    final c = _contenedor(
      extraccion: _FakeExtraccion(resultado: [
        const TareaPropuesta(titulo: 'Comprar pan'),
        TareaPropuesta(titulo: 'Entregar informe', venceEn: DateTime(2026, 6, 1)),
      ]),
    );

    await _ctrl(c).interpretar('comprar pan\nentregar informe el lunes');

    final estado = c.read(extraccionTareasControllerProvider);
    expect(estado.fase, FaseExtraccion.revision);
    expect(estado.propuestas, hasLength(2));
    expect(estado.sinTareas, isFalse);
  });

  test('interpretar sin tareas → revisión vacía (sinTareas=true)', () async {
    final c = _contenedor(extraccion: _FakeExtraccion(resultado: const []));

    await _ctrl(c).interpretar('la fotosíntesis es un proceso');

    final estado = c.read(extraccionTareasControllerProvider);
    expect(estado.fase, FaseExtraccion.revision);
    expect(estado.sinTareas, isTrue);
  });

  test('interpretar con texto vacío → error, sin llamar al cerebro', () async {
    final c = _contenedor(extraccion: _FakeExtraccion());

    await _ctrl(c).interpretar('   ');

    final estado = c.read(extraccionTareasControllerProvider);
    expect(estado.fase, FaseExtraccion.error);
    expect(estado.error, isNotNull);
  });

  test('interpretar con fallo de red → fase error con mensaje', () async {
    final c = _contenedor(
      extraccion: _FakeExtraccion(error: MatixApiException(0, 'sin cerebro')),
    );

    await _ctrl(c).interpretar('algo');

    final estado = c.read(extraccionTareasControllerProvider);
    expect(estado.fase, FaseExtraccion.error);
    expect(estado.error, contains('sin cerebro'));
  });

  test('ediciones: título, fecha, quitar fecha, proyecto, eliminar', () async {
    final c = _contenedor(
      extraccion: _FakeExtraccion(resultado: [
        TareaPropuesta(titulo: 'A', venceEn: DateTime(2026, 6, 1)),
        const TareaPropuesta(titulo: 'B'),
      ]),
    );
    await _ctrl(c).interpretar('texto');

    _ctrl(c).editarTitulo(0, 'A corregida');
    _ctrl(c).quitarFecha(0);
    _ctrl(c).ponerFecha(1, DateTime(2026, 7, 15));
    _ctrl(c).asignarProyecto(1, 'proj-1');

    var estado = c.read(extraccionTareasControllerProvider);
    expect(estado.propuestas[0].titulo, 'A corregida');
    expect(estado.propuestas[0].venceEn, isNull);
    expect(estado.propuestas[1].venceEn, DateTime(2026, 7, 15));
    expect(estado.propuestas[1].proyectoId, 'proj-1');

    _ctrl(c).eliminar(0);
    estado = c.read(extraccionTareasControllerProvider);
    expect(estado.propuestas, hasLength(1));
    expect(estado.propuestas.first.titulo, 'B');
  });

  test('crear → fase creado, crea todas con título/fecha/proyecto', () async {
    final fakeTareas = _FakeTareas();
    final c = _contenedor(
      extraccion: _FakeExtraccion(resultado: [
        const TareaPropuesta(titulo: 'Comprar pan'),
        TareaPropuesta(
          titulo: 'Entregar informe',
          venceEn: DateTime(2026, 6, 1),
          proyectoId: 'proj-1',
        ),
      ]),
      tareas: fakeTareas,
    );
    await _ctrl(c).interpretar('texto');

    await _ctrl(c).crear();

    final estado = c.read(extraccionTareasControllerProvider);
    expect(estado.fase, FaseExtraccion.creado);
    expect(estado.creadas, 2);
    expect(fakeTareas.creadas, hasLength(2));
    expect(fakeTareas.creadas[1]['titulo'], 'Entregar informe');
    expect(fakeTareas.creadas[1]['venceEn'], DateTime(2026, 6, 1));
    expect(fakeTareas.creadas[1]['proyectoId'], 'proj-1');
  });

  test('crear con fallo parcial → vuelve a revisión con error', () async {
    final fakeTareas = _FakeTareas(fallaEnLlamada: 2);
    final c = _contenedor(
      extraccion: _FakeExtraccion(resultado: const [
        TareaPropuesta(titulo: 'Una'),
        TareaPropuesta(titulo: 'Dos'),
        TareaPropuesta(titulo: 'Tres'),
      ]),
      tareas: fakeTareas,
    );
    await _ctrl(c).interpretar('texto');

    await _ctrl(c).crear();

    final estado = c.read(extraccionTareasControllerProvider);
    expect(estado.fase, FaseExtraccion.revision);
    expect(estado.error, contains('Creé 1'));
    // La primera sí se creó; la segunda falló y cortamos.
    expect(fakeTareas.creadas, hasLength(1));
  });

  test('reiniciar vuelve a fase inicial', () async {
    final c = _contenedor(
      extraccion: _FakeExtraccion(resultado: const [
        TareaPropuesta(titulo: 'X'),
      ]),
    );
    await _ctrl(c).interpretar('texto');
    expect(c.read(extraccionTareasControllerProvider).fase,
        FaseExtraccion.revision);

    _ctrl(c).reiniciar();
    expect(c.read(extraccionTareasControllerProvider).fase,
        FaseExtraccion.inicial);
  });
}
