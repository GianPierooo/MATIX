import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matix/features/captura_camara/application/captura_controller.dart';
import 'package:matix/features/captura_camara/data/ocr_service.dart';

/// Tests del `CapturaController` (Capa 7-A). No tocamos ML Kit real
/// (necesita platform channel): sustituimos `ocrServiceProvider` por un
/// fake que `implements OcrService` — al implementar la interfaz nunca
/// se construye el `TextRecognizer` nativo.

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

/// Crea una imagen temporal para que `procesarFoto` tenga algo que
/// borrar en el `finally`. Devuelve la ruta.
Future<String> _fotoTemp() async {
  final dir = Directory.systemTemp.createTempSync('matix_ocr_test_');
  final f = File('${dir.path}/foto.jpg');
  await f.writeAsBytes([0xff, 0xd8, 0xff, 0xd9]);
  return f.path;
}

ProviderContainer _contenedor(OcrService fake) {
  final c = ProviderContainer(
    overrides: [ocrServiceProvider.overrideWithValue(fake)],
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

  test('procesarFoto sin texto → listo pero vacío=true', () async {
    final c = _contenedor(_FakeOcr(texto: '   '));
    final ruta = await _fotoTemp();

    await c.read(capturaControllerProvider.notifier).procesarFoto(ruta);

    final estado = c.read(capturaControllerProvider);
    expect(estado.fase, FaseCaptura.listo);
    expect(estado.vacio, isTrue);
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
