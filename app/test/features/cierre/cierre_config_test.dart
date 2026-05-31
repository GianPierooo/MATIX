import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/cierre/providers/cierre_providers.dart';
import 'package:matix/features/rituales/data/rituales_repository.dart';

/// Tests del `CierreConfigController` (Push Capa 3a). Como el del briefing:
/// la config vive en el cerebro y el controller carga/persiste ahí.

class _FakeRepo implements RitualesRepository {
  _FakeRepo(this._actual);
  RitualConfig? _actual;
  final List<RitualConfig> guardados = [];

  @override
  Future<RitualConfig?> obtener(String ritual) async => _actual;

  @override
  Future<void> actualizar(
    String ritual, {
    required bool activo,
    required int hora,
    required int minuto,
    int? diaSemana,
  }) async {
    final c =
        (activo: activo, hora: hora, minuto: minuto, diaSemana: diaSemana);
    _actual = c;
    guardados.add(c);
  }
}

ProviderContainer _con(_FakeRepo repo) {
  final c = ProviderContainer(
    overrides: [ritualesRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('carga la config del cerebro al arrancar', () async {
    final c = _con(_FakeRepo((activo: false, hora: 21, minuto: 45, diaSemana: null)));
    await c.read(cierreConfigProvider.notifier).ready;
    final cfg = c.read(cierreConfigProvider);
    expect(cfg.activo, isFalse);
    expect(cfg.hora, 21);
    expect(cfg.minuto, 45);
  });

  test('default ON 22:00 si el cerebro no responde', () async {
    final c = _con(_FakeRepo(null));
    await c.read(cierreConfigProvider.notifier).ready;
    final cfg = c.read(cierreConfigProvider);
    expect(cfg.activo, isTrue);
    expect(cfg.hora, 22);
    expect(cfg.minuto, 0);
  });

  test('cambiarHora persiste la nueva hora en el cerebro', () async {
    final repo = _FakeRepo((activo: true, hora: 22, minuto: 0, diaSemana: null));
    final c = _con(repo);
    await c.read(cierreConfigProvider.notifier).ready;

    await c.read(cierreConfigProvider.notifier).cambiarHora(21, 30);

    expect(c.read(cierreConfigProvider).hora, 21);
    expect(repo.guardados.last.hora, 21);
    expect(repo.guardados.last.minuto, 30);
  });
}
