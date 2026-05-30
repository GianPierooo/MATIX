import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/captura_camara/application/extraccion_recibo_controller.dart';
import 'package:matix/features/captura_camara/data/extraccion_recibo_repository.dart';
import 'package:matix/features/captura_camara/domain/recibo_propuesto.dart';
import 'package:matix/features/finanzas/data/movimientos_repository.dart';
import 'package:matix/features/finanzas/domain/movimiento.dart';
import 'package:matix/features/finanzas/providers/movimientos_providers.dart';

/// Tests del flujo recibo → gasto (Finanzas-2): que interpretar deje la
/// propuesta lista para revisar y que confirmar cree un GASTO en Finanzas
/// con los valores revisados. Sin red: repos falsos.

class _FakeReciboRepo implements ExtraccionReciboRepository {
  _FakeReciboRepo(this.propuesta);
  final ReciboPropuesto propuesta;
  @override
  Future<ReciboPropuesto> extraer(String texto) async => propuesta;
}

class _FakeMovRepo implements MovimientosRepository {
  TipoMovimiento? tipo;
  double? monto;
  String? categoria;
  DateTime? fecha;
  String? nota;
  int creados = 0;

  @override
  Future<Movimiento> crear({
    required TipoMovimiento tipo,
    required double monto,
    required String categoria,
    required DateTime fecha,
    String nota = '',
  }) async {
    this.tipo = tipo;
    this.monto = monto;
    this.categoria = categoria;
    this.fecha = fecha;
    this.nota = nota;
    creados++;
    return Movimiento(
      id: 'm1',
      tipo: tipo,
      monto: monto,
      categoria: categoria,
      fecha: fecha,
      nota: nota,
      creadoEn: fecha,
      actualizadoEn: fecha,
    );
  }

  // No usados por el controller; devolvemos vacío para no romper si algo
  // invalida la lista.
  @override
  Future<List<Movimiento>> listar() async => const [];
  @override
  Future<Movimiento> obtener(String id) => throw UnimplementedError();
  @override
  Future<Movimiento> actualizar({
    required String id,
    required TipoMovimiento tipo,
    required double monto,
    required String categoria,
    required DateTime fecha,
    String nota = '',
  }) =>
      throw UnimplementedError();
  @override
  Future<void> borrar(String id) async {}
}

ProviderContainer _contenedor({
  required ReciboPropuesto propuesta,
  required MovimientosRepository mov,
}) {
  final c = ProviderContainer(
    overrides: [
      extraccionReciboRepositoryProvider
          .overrideWithValue(_FakeReciboRepo(propuesta)),
      movimientosRepoProvider.overrideWithValue(mov),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('interpretar deja la propuesta en revisión', () async {
    final c = _contenedor(
      propuesta: ReciboPropuesto(
        monto: 45.90,
        fecha: DateTime(2026, 5, 10),
        comercio: 'XYZ',
        categoria: 'Comida',
      ),
      mov: _FakeMovRepo(),
    );
    await c
        .read(extraccionReciboControllerProvider.notifier)
        .interpretar('texto del recibo');

    final estado = c.read(extraccionReciboControllerProvider);
    expect(estado.fase, FaseRecibo.revision);
    expect(estado.propuesta!.monto, 45.90);
    expect(estado.propuesta!.categoria, 'Comida');
  });

  test('interpretar con texto vacío → error sin llamar al cerebro', () async {
    final c = _contenedor(
      propuesta: const ReciboPropuesto(),
      mov: _FakeMovRepo(),
    );
    await c
        .read(extraccionReciboControllerProvider.notifier)
        .interpretar('   ');
    expect(c.read(extraccionReciboControllerProvider).fase, FaseRecibo.error);
  });

  test('confirmar crea un GASTO en Finanzas con los valores revisados',
      () async {
    final mov = _FakeMovRepo();
    final c = _contenedor(
      propuesta: ReciboPropuesto(monto: 45.90, fecha: DateTime(2026, 5, 10)),
      mov: mov,
    );
    final ctrl = c.read(extraccionReciboControllerProvider.notifier);
    await ctrl.interpretar('texto');
    await ctrl.crear(
      monto: 50,
      categoria: 'Comida',
      fecha: DateTime(2026, 5, 10),
      nota: 'XYZ',
    );

    expect(c.read(extraccionReciboControllerProvider).fase, FaseRecibo.creado);
    expect(mov.creados, 1);
    expect(mov.tipo, TipoMovimiento.gasto);
    expect(mov.monto, 50);
    expect(mov.categoria, 'Comida');
    expect(mov.fecha, DateTime(2026, 5, 10));
    expect(mov.nota, 'XYZ');
  });

  test('confirmar con monto <= 0 no crea nada (no inventa cifras)', () async {
    final mov = _FakeMovRepo();
    final c = _contenedor(propuesta: const ReciboPropuesto(), mov: mov);
    final ctrl = c.read(extraccionReciboControllerProvider.notifier);
    await ctrl.crear(
      monto: 0,
      categoria: 'Comida',
      fecha: DateTime(2026, 5, 10),
    );
    expect(mov.creados, 0);
    final estado = c.read(extraccionReciboControllerProvider);
    expect(estado.fase, FaseRecibo.revision);
    expect(estado.error, isNotNull);
  });
}
