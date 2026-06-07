import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/modelos/data/modelos_repository.dart';
import 'package:matix/features/modelos/providers/modelos_providers.dart';

/// Tests del selector de modelo. La fuente de verdad es el cerebro; acá
/// fakeamos el repo y verificamos carga, agrupación por proveedor, la
/// selección (optimista + persistida), el modo Automático y el par
/// barato/fuerte.

const _catalogo = [
  ModeloLlm(id: 'gpt-5.5', etiqueta: 'GPT-5.5', proveedor: 'openai'),
  ModeloLlm(id: 'gpt-4o-mini', etiqueta: 'GPT-4o mini', proveedor: 'openai'),
  ModeloLlm(
      id: 'claude-opus-4-8', etiqueta: 'Claude Opus 4.8', proveedor: 'anthropic'),
];

class _FakeRepo implements ModelosRepository {
  _FakeRepo(this._sel);
  String _sel;
  String barato = 'gpt-4o-mini';
  String fuerte = 'claude-opus-4-8';
  String proveedor = 'auto';

  ModelosEstado get _estado => (
        modelos: _catalogo,
        seleccionado: _sel,
        barato: barato,
        fuerte: fuerte,
        proveedorPreferido: proveedor,
      );

  @override
  Future<ModelosEstado> estado() async => _estado;

  @override
  Future<ModelosEstado> seleccionar(String id) async {
    _sel = id;
    return _estado;
  }

  @override
  Future<ModelosEstado> fijarPar({String? barato, String? fuerte}) async {
    if (barato != null) this.barato = barato;
    if (fuerte != null) this.fuerte = fuerte;
    return _estado;
  }

  @override
  Future<ModelosEstado> fijarProveedor(String proveedor) async {
    this.proveedor = proveedor;
    return _estado;
  }
}

ProviderContainer _con(_FakeRepo repo) {
  final c = ProviderContainer(
    overrides: [modelosRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('carga el catálogo, el seleccionado y el par del cerebro', () async {
    final c = _con(_FakeRepo('gpt-4o-mini'));
    await c.read(modelosProvider.notifier).ready;
    final s = c.read(modelosProvider);
    expect(s.modelos.length, 3);
    expect(s.seleccionado, 'gpt-4o-mini');
    expect(s.modeloActual?.etiqueta, 'GPT-4o mini');
    expect(s.esAuto, isFalse);
    expect(s.barato, 'gpt-4o-mini');
    expect(s.fuerte, 'claude-opus-4-8');
  });

  test('agrupa por proveedor', () async {
    final c = _con(_FakeRepo('gpt-5.5'));
    await c.read(modelosProvider.notifier).ready;
    final grupos = c.read(modelosProvider).porProveedor;
    expect(grupos['openai']!.length, 2);
    expect(grupos['anthropic']!.length, 1);
    expect(grupos['anthropic']!.first.proveedorEtiqueta, 'Anthropic (Claude)');
  });

  test('seleccionar persiste y actualiza el estado', () async {
    final c = _con(_FakeRepo('gpt-5.5'));
    await c.read(modelosProvider.notifier).ready;
    await c.read(modelosProvider.notifier).seleccionar('claude-opus-4-8');
    expect(c.read(modelosProvider).seleccionado, 'claude-opus-4-8');
    expect(c.read(modelosProvider).modeloActual?.proveedor, 'anthropic');
  });

  test('seleccionar "auto" activa el modo Automático', () async {
    final c = _con(_FakeRepo('gpt-5.5'));
    await c.read(modelosProvider.notifier).ready;
    await c.read(modelosProvider.notifier).seleccionar(kModeloAuto);
    final s = c.read(modelosProvider);
    expect(s.esAuto, isTrue);
    expect(s.seleccionado, 'auto');
    // En auto no hay "modeloActual" del catálogo.
    expect(s.modeloActual, isNull);
  });

  test('fijarPar cambia el modelo barato/fuerte', () async {
    final c = _con(_FakeRepo(kModeloAuto));
    await c.read(modelosProvider.notifier).ready;
    await c.read(modelosProvider.notifier).fijarPar(fuerte: 'gpt-5.5');
    final s = c.read(modelosProvider);
    expect(s.fuerte, 'gpt-5.5');
    expect(s.etiquetaDe('gpt-5.5'), 'GPT-5.5');
  });
}
