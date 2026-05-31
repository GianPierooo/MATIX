import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/repaso/providers/repaso_providers.dart';
import 'package:matix/features/rituales/data/rituales_repository.dart';

/// Tests del `RepasoConfigController` (4º ritual, semanal). Como el del
/// briefing/cierre pero además persiste el DÍA de la semana. La config vive
/// en el cerebro; el controller carga/persiste ahí.

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
  test('default ON, domingo 20:00 si el cerebro no responde', () async {
    final c = _con(_FakeRepo(null));
    await c.read(repasoConfigProvider.notifier).ready;
    final cfg = c.read(repasoConfigProvider);
    expect(cfg.activo, isTrue);
    expect(cfg.diaSemana, 7);
    expect(cfg.hora, 20);
    expect(cfg.diaNombre, 'Domingo');
  });

  test('carga la config del cerebro (incluye el día)', () async {
    final c = _con(
      _FakeRepo((activo: true, hora: 18, minuto: 30, diaSemana: 5)),
    );
    await c.read(repasoConfigProvider.notifier).ready;
    final cfg = c.read(repasoConfigProvider);
    expect(cfg.diaSemana, 5);
    expect(cfg.diaNombre, 'Viernes');
    expect(cfg.horaFormateada, '18:30');
  });

  test('cambiarDia persiste el día en el cerebro', () async {
    final repo = _FakeRepo((activo: true, hora: 20, minuto: 0, diaSemana: 7));
    final c = _con(repo);
    await c.read(repasoConfigProvider.notifier).ready;

    await c.read(repasoConfigProvider.notifier).cambiarDia(3);

    expect(c.read(repasoConfigProvider).diaSemana, 3);
    expect(repo.guardados.last.diaSemana, 3);
    // Y se manda con el día (no queda null).
    expect(repo.guardados.last.activo, isTrue);
  });

  test('activar(false) apaga y persiste', () async {
    final repo = _FakeRepo((activo: true, hora: 20, minuto: 0, diaSemana: 7));
    final c = _con(repo);
    await c.read(repasoConfigProvider.notifier).ready;
    await c.read(repasoConfigProvider.notifier).activar(false);
    expect(c.read(repasoConfigProvider).activo, isFalse);
    expect(repo.guardados.last.activo, isFalse);
  });
}
