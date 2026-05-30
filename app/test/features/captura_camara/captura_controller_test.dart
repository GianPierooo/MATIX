import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matix/features/captura_camara/application/captura_controller.dart';
import 'package:matix/features/captura_camara/data/clasificacion_repository.dart';
import 'package:matix/features/captura_camara/data/ocr_service.dart';
import 'package:matix/features/captura_camara/domain/destino_ocr.dart';

/// Tests del `CapturaController` (cámara inteligente). No tocamos ML Kit
/// real (necesita platform channel) ni el cerebro: sustituimos
/// `ocrServiceProvider` y `clasificacionRepositoryProvider` por fakes —
/// al implementar la interfaz nunca se construye el nativo ni se pega a
/// la red.

class _FakeOcr implements OcrService {
  _FakeOcr({this.texto = '', this.lanza = false});
  final String texto;
  final bool lanza;

  @override
  Future<String> extraerTexto(String rutaImagen) async {
    if (lanza) throw Exception('boom');
    return texto;
  }

  @override
  Future<void> dispose() async {}
}

class _FakeClasif implements ClasificacionRepository {
  _FakeClasif({this.destino = DestinoOcr.apunte, this.lanza = false});
  final DestinoOcr destino;
  final bool lanza;
  int llamadas = 0;

  @override
  Future<DestinoOcr> clasificar(String texto) async {
    llamadas++;
    if (lanza) throw Exception('sin red');
    return destino;
  }
}

/// Crea una imagen temporal para que `procesarFoto` tenga algo que
/// borrar en el `finally`. Devuelve la ruta.
Future<String> _fotoTemp() async {
  final dir = Directory.systemTemp.createTempSync('matix_ocr_test_');
  final f = File('${dir.path}/foto.jpg');
  await f.writeAsBytes([0xff, 0xd8, 0xff, 0xd9]);
  return f.path;
}

ProviderContainer _contenedor(OcrService fake, {ClasificacionRepository? clasif}) {
  final c = ProviderContainer(
    overrides: [
      ocrServiceProvider.overrideWithValue(fake),
      clasificacionRepositoryProvider.overrideWithValue(clasif ?? _FakeClasif()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('estado inicial es fase cámara, sin texto ni error', () {
    final c = _contenedor(_FakeOcr());
    final estado = c.read(capturaControllerProvider);
    expect(estado.fase, FaseCaptura.camara);
    expect(estado.texto, '');
    expect(estado.error, isNull);
    expect(estado.vacio, isFalse);
  });

  test('procesarFoto con texto → fase listo y texto poblado', () async {
    final c = _contenedor(_FakeOcr(texto: 'Comprar pan\nLlamar a Ana'));
    final ruta = await _fotoTemp();

    await c.read(capturaControllerProvider.notifier).procesarFoto(ruta);

    final estado = c.read(capturaControllerProvider);
    expect(estado.fase, FaseCaptura.listo);
    expect(estado.texto, 'Comprar pan\nLlamar a Ana');
    expect(estado.vacio, isFalse);
    // La foto se borra tras procesar (no sale del teléfono).
    expect(File(ruta).existsSync(), isFalse);
  });

  // ─── Clasificación: el texto se rutea a cada uno de los tres flujos ──
  for (final destino in DestinoOcr.values) {
    test('clasifica a $destino → destino sugerido en el estado', () async {
      final c = _contenedor(
        _FakeOcr(texto: 'algo con texto'),
        clasif: _FakeClasif(destino: destino),
      );
      final ruta = await _fotoTemp();

      await c.read(capturaControllerProvider.notifier).procesarFoto(ruta);

      final estado = c.read(capturaControllerProvider);
      expect(estado.fase, FaseCaptura.listo);
      expect(estado.destino, destino);
    });
  }

  test('clasificación que falla → cae a apunte (best-effort), no atasca',
      () async {
    final c = _contenedor(
      _FakeOcr(texto: 'un texto cualquiera'),
      clasif: _FakeClasif(lanza: true),
    );
    final ruta = await _fotoTemp();

    await c.read(capturaControllerProvider.notifier).procesarFoto(ruta);

    final estado = c.read(capturaControllerProvider);
    expect(estado.fase, FaseCaptura.listo);
    expect(estado.texto, 'un texto cualquiera');
    expect(estado.destino, DestinoOcr.apunte);
  });

  test('procesarFoto sin texto → listo, apunte y sin clasificar', () async {
    final clasif = _FakeClasif(destino: DestinoOcr.tareas);
    final c = _contenedor(_FakeOcr(texto: '   '), clasif: clasif);
    final ruta = await _fotoTemp();

    await c.read(capturaControllerProvider.notifier).procesarFoto(ruta);

    final estado = c.read(capturaControllerProvider);
    expect(estado.fase, FaseCaptura.listo);
    expect(estado.vacio, isTrue);
    // Sin texto no hay nada que clasificar: catch-all apunte, y NO se
    // llama al cerebro.
    expect(estado.destino, DestinoOcr.apunte);
    expect(clasif.llamadas, 0);
  });

  test('procesarFoto que lanza → fase error con mensaje', () async {
    final c = _contenedor(_FakeOcr(lanza: true));
    final ruta = await _fotoTemp();

    await c.read(capturaControllerProvider.notifier).procesarFoto(ruta);

    final estado = c.read(capturaControllerProvider);
    expect(estado.fase, FaseCaptura.error);
    expect(estado.error, isNotNull);
    expect(estado.vacio, isFalse);
    // Aun en error, la foto temporal se limpia.
    expect(File(ruta).existsSync(), isFalse);
  });

  test('reiniciar vuelve a fase cámara', () async {
    final c = _contenedor(_FakeOcr(texto: 'algo'));
    final ruta = await _fotoTemp();
    await c.read(capturaControllerProvider.notifier).procesarFoto(ruta);
    expect(c.read(capturaControllerProvider).fase, FaseCaptura.listo);

    c.read(capturaControllerProvider.notifier).reiniciar();
    expect(c.read(capturaControllerProvider).fase, FaseCaptura.camara);
  });
}
