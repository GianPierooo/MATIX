import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matix/api/matix_client.dart';
import 'package:matix/features/apuntes/application/guardar_apunte_controller.dart';
import 'package:matix/features/matix/data/captura_apunte_repository.dart';
import 'package:matix/features/matix/providers/captura_apunte_providers.dart';

/// Tests del `GuardarApunteController` (Capa 7 — OCR foto→apunte
/// unificado a on-device). No tocamos red: sustituimos el repo que
/// llama a `/matix/capturar-apunte` por un fake que implementa su
/// única interfaz.

class _FakeCaptura implements CapturaApunteRepository {
  _FakeCaptura({this.resultado, this.error});
  final ApunteCapturado? resultado;
  final Object? error;
  final List<String> recibidos = [];

  @override
  Future<ApunteCapturado> capturar(String texto) async {
    recibidos.add(texto);
    if (error != null) throw error!;
    return resultado ??
        const ApunteCapturado(
          tipo: 'apunte',
          id: 'a1',
          titulo: 'Apunte',
          etiquetas: [],
          general: true,
        );
  }
}

ProviderContainer _contenedor(CapturaApunteRepository repo) {
  final c = ProviderContainer(
    overrides: [capturaApunteRepoProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
}

GuardarApunteController _ctrl(ProviderContainer c) =>
    c.read(guardarApunteControllerProvider.notifier);

void main() {
  test('estado inicial es fase inicial, sin resultado ni error', () {
    final c = _contenedor(_FakeCaptura());
    final estado = c.read(guardarApunteControllerProvider);
    expect(estado.fase, FaseGuardarApunte.inicial);
    expect(estado.resultado, isNull);
    expect(estado.error, isNull);
  });

  test('guardar con texto → fase guardado con el apunte clasificado',
      () async {
    final fake = _FakeCaptura(
      resultado: const ApunteCapturado(
        tipo: 'apunte',
        id: 'a9',
        titulo: 'Resumen de clase',
        etiquetas: ['clase'],
        general: false,
        cursoNombre: 'Cálculo',
      ),
    );
    final c = _contenedor(fake);

    await _ctrl(c).guardar('  apuntes de la pizarra  ');

    final estado = c.read(guardarApunteControllerProvider);
    expect(estado.fase, FaseGuardarApunte.guardado);
    expect(estado.resultado?.id, 'a9');
    expect(estado.resultado?.destinoLabel, 'Guardado en el curso Cálculo');
    // Mandó el texto trimmeado, no el original con espacios.
    expect(fake.recibidos.single, 'apuntes de la pizarra');
  });

  test('guardar con texto vacío → error, sin llamar al cerebro', () async {
    final fake = _FakeCaptura();
    final c = _contenedor(fake);

    await _ctrl(c).guardar('   ');

    final estado = c.read(guardarApunteControllerProvider);
    expect(estado.fase, FaseGuardarApunte.error);
    expect(estado.error, isNotNull);
    expect(fake.recibidos, isEmpty);
  });

  test('guardar con fallo de API → fase error con mensaje', () async {
    final c = _contenedor(
      _FakeCaptura(error: MatixApiException(503, 'sin OPENAI_API_KEY')),
    );

    await _ctrl(c).guardar('algo');

    final estado = c.read(guardarApunteControllerProvider);
    expect(estado.fase, FaseGuardarApunte.error);
    expect(estado.error, contains('sin OPENAI_API_KEY'));
  });

  test('guardar con error inesperado → fase error', () async {
    final c = _contenedor(_FakeCaptura(error: StateError('boom')));

    await _ctrl(c).guardar('algo');

    expect(c.read(guardarApunteControllerProvider).fase,
        FaseGuardarApunte.error);
  });

  test('reiniciar vuelve a fase inicial', () async {
    final c = _contenedor(_FakeCaptura());
    await _ctrl(c).guardar('algo');
    expect(c.read(guardarApunteControllerProvider).fase,
        FaseGuardarApunte.guardado);

    _ctrl(c).reiniciar();
    expect(c.read(guardarApunteControllerProvider).fase,
        FaseGuardarApunte.inicial);
  });
}
