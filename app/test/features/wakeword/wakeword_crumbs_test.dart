import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/wakeword/data/wakeword_crumbs.dart';

void main() {
  late Directory tmp;
  late File archivo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wakeword_crumbs_test');
    archivo = File('${tmp.path}/crumb.txt');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('sin rastro previo no hay muerte', () async {
    final c = WakeWordCrumbs(archivo: archivo);
    expect(await c.muerteDeActivacion(), isNull);
  });

  test('una migaja de paso peligroso se detecta como muerte', () async {
    final c = WakeWordCrumbs(archivo: archivo);
    await c.preparar();
    c.marca('sesion:mel'); // murió creando la sesión del melspectrograma
    expect(await c.leer(), 'sesion:mel');
    expect(await c.muerteDeActivacion(), 'sesion:mel');
  });

  test('estados seguros NO se reportan como muerte', () async {
    for (final seguro in ['apagado', 'escuchando-ok', 'inferencia-ok']) {
      final c = WakeWordCrumbs(archivo: archivo);
      await c.preparar();
      c.marca(seguro);
      expect(await c.muerteDeActivacion(), isNull, reason: seguro);
    }
  });

  test('limpiar borra el rastro', () async {
    final c = WakeWordCrumbs(archivo: archivo);
    await c.preparar();
    c.marca('mic-start');
    await c.limpiar();
    expect(await c.leer(), isNull);
    expect(await c.muerteDeActivacion(), isNull);
  });

  test('la última migaja gana (se sobrescribe)', () async {
    final c = WakeWordCrumbs(archivo: archivo);
    await c.preparar();
    c.marca('permiso');
    c.marca('cargar');
    c.marca('sesion:embedding');
    expect(await c.leer(), 'sesion:embedding');
  });
}
