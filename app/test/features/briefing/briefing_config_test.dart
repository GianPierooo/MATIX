import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/briefing/providers/briefing_providers.dart';
import 'package:matix/features/rituales/data/rituales_repository.dart';

/// Tests del `BriefingConfigController` (Push Capa 3a).
///
/// Ahora la config vive en el CEREBRO: el controller carga del servidor y
/// persiste cada cambio ahí (el push lo dispara el scheduler). Usamos un
/// `RitualesRepository` fake que guarda la config y registra los PATCH.

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
  }) async {
    final c = (activo: activo, hora: hora, minuto: minuto);
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
    final c = _con(_FakeRepo((activo: false, hora: 7, minuto: 30)));
    await c.read(briefingConfigProvider.notifier).ready;
    final cfg = c.read(briefingConfigProvider);
    expect(cfg.activo, isFalse);
    expect(cfg.hora, 7);
    expect(cfg.minuto, 30);
  });

  test('si el cerebro no responde, queda el default ON 08:00', () async {
    final c = _con(_FakeRepo(null)); // obtener devuelve null
    await c.read(briefingConfigProvider.notifier).ready;
    final cfg = c.read(briefingConfigProvider);
    expect(cfg.activo, isTrue);
    expect(cfg.hora, 8);
    expect(cfg.minuto, 0);
  });

  test('activar(false) persiste activo=false en el cerebro', () async {
    final repo = _FakeRepo((activo: true, hora: 8, minuto: 0));
    final c = _con(repo);
    await c.read(briefingConfigProvider.notifier).ready;

    await c.read(briefingConfigProvider.notifier).activar(false);

    expect(c.read(briefingConfigProvider).activo, isFalse);
    expect(repo.guardados.last.activo, isFalse);
  });

  test('cambiarHora persiste la nueva hora en el cerebro', () async {
    final repo = _FakeRepo((activo: true, hora: 8, minuto: 0));
    final c = _con(repo);
    await c.read(briefingConfigProvider.notifier).ready;

    await c.read(briefingConfigProvider.notifier).cambiarHora(7, 15);

    final cfg = c.read(briefingConfigProvider);
    expect(cfg.hora, 7);
    expect(cfg.minuto, 15);
    expect(repo.guardados.last.hora, 7);
    expect(repo.guardados.last.minuto, 15);
  });
}
