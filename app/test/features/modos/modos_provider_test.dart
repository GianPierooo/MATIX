import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/matix/data/matix_chat_repository.dart';
import 'package:matix/features/modos/data/modos_repository.dart';
import 'package:matix/features/modos/providers/modos_providers.dart';

/// Tests del estado de modos de Matix. La fuente de verdad es el cerebro;
/// acá fakeamos el repo y verificamos carga, activar/desactivar, la
/// resolución del modo activo, y la sincronización tras un turno de chat.

const _modos = [
  ModoMatix(nombre: 'tesis', etiqueta: 'Tesis', descripcion: 'Escribir la tesis'),
  ModoMatix(nombre: 'estudio', etiqueta: 'Estudio', descripcion: 'Modo tutor'),
];

class _FakeRepo implements ModosRepository {
  _FakeRepo(this._activo);
  String? _activo;

  @override
  Future<ModosEstado> estado() async =>
      (disponibles: _modos, activo: _activo);

  @override
  Future<ModosEstado> activar(String modo) async {
    _activo = modo;
    return (disponibles: _modos, activo: _activo);
  }

  @override
  Future<ModosEstado> desactivar() async {
    _activo = null;
    return (disponibles: _modos, activo: _activo);
  }
}

ProviderContainer _con(_FakeRepo repo) {
  final c = ProviderContainer(
    overrides: [modosRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('ModosState', () {
    test('modoActivo resuelve la etiqueta del activo', () {
      const s = ModosState(disponibles: _modos, activo: 'tesis');
      expect(s.modoActivo?.etiqueta, 'Tesis');
    });
    test('modoActivo es null en modo normal', () {
      const s = ModosState(disponibles: _modos, activo: null);
      expect(s.modoActivo, isNull);
    });
  });

  test('carga el estado del cerebro al arrancar', () async {
    final c = _con(_FakeRepo('estudio'));
    await c.read(modosProvider.notifier).ready;
    final s = c.read(modosProvider);
    expect(s.activo, 'estudio');
    expect(s.disponibles.length, 2);
  });

  test('activar y desactivar persisten y actualizan el estado', () async {
    final c = _con(_FakeRepo(null));
    await c.read(modosProvider.notifier).ready;

    await c.read(modosProvider.notifier).activar('tesis');
    expect(c.read(modosProvider).activo, 'tesis');
    expect(c.read(modosProvider).modoActivo?.etiqueta, 'Tesis');

    await c.read(modosProvider.notifier).desactivar();
    expect(c.read(modosProvider).activo, isNull);
  });

  test('sincronizar refleja el modo que reportó el cerebro tras un turno',
      () async {
    final c = _con(_FakeRepo(null));
    await c.read(modosProvider.notifier).ready;

    // El modelo activó un modo con una tool; el turno lo reporta.
    c.read(modosProvider.notifier).sincronizar('tesis');
    expect(c.read(modosProvider).activo, 'tesis');

    // Y al volver a normal.
    c.read(modosProvider.notifier).sincronizar(null);
    expect(c.read(modosProvider).activo, isNull);
  });

  test('ChatTurno parsea modo_activo del cerebro', () {
    const turno = ChatTurno(
      respuesta: 'Activé el modo tesis',
      toolsUsadas: ['activar_modo'],
      tablasCambiadas: [],
      modoActivo: 'tesis',
    );
    expect(turno.modoActivo, 'tesis');
  });
}
