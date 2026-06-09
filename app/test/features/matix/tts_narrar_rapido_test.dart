import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matix/features/matix/data/tts_service.dart';

/// `narrarRapido` es la cadena DEVICE-FIRST para la cámara en vivo:
///   - dispositivo OK   → suena al toque, sin red.
///   - dispositivo fail → respaldo cloud.
///   - ambos fallan     → `onFallo` (sigue narrando texto).
/// Y SIN epoca-guard que estrangulaba el respaldo (era el bug previo).
///
/// Verificamos: ruta correcta, callbacks correctos, ultimoEvento con
/// proveedor + éxito + motivo (instrumentación).

class _FakeReproductor implements ReproductorAudio {
  int reproducirCount = 0;
  int detenerCount = 0;
  @override
  Future<void> reproducir(List<int> mp3) async => reproducirCount++;
  @override
  Future<void> detener() async => detenerCount++;
  @override
  Stream<bool> get reproduciendo => const Stream.empty();
  @override
  Stream<void> get alCompletar => const Stream.empty();
  @override
  Future<void> liberar() async {}
}

class _VozFake implements VozDispositivo {
  _VozFake({this.ok = true});
  bool ok;
  String? idioma = 'es-419';
  int hablo = 0;
  int detenido = 0;
  int preparado = 0;
  @override
  Future<bool> hablar(String texto) async {
    hablo++;
    return ok;
  }

  @override
  Future<bool> hablarYEsperar(String texto) async {
    hablo++;
    return ok;
  }

  @override
  Future<void> detener() async {
    detenido++;
  }

  @override
  Future<bool> preparar() async {
    preparado++;
    return ok;
  }

  @override
  String? get idiomaActivo => idioma;
}

Future<void> _tick([int ms = 50]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  test('device-first: cuando el dispositivo habla, el cloud NO se llama',
      () async {
    var huboHttp = 0;
    final mock = MockClient((_) async {
      huboHttp++;
      return http.Response.bytes([1, 2, 3], 200);
    });
    final rep = _FakeReproductor();
    final voz = _VozFake();
    final tts = TtsService(inner: mock, reproductor: rep, vozDispositivo: voz);

    var ok = 0, fallo = 0, cloud = 0;
    tts.narrarRapido(
      'hola',
      onFallo: () => fallo++,
      onDispositivo: () => ok++,
      onCloud: () => cloud++,
    );
    await _tick();

    expect(voz.hablo, 1);
    expect(huboHttp, 0); // NO se llamó al cloud
    expect(rep.reproducirCount, 0); // NO sonó mp3
    expect(ok, 1);
    expect(fallo, 0);
    expect(cloud, 0);
    expect(tts.ultimoEvento?.proveedor, ProveedorTts.dispositivo);
    expect(tts.ultimoEvento?.exito, isTrue);
    await tts.dispose();
  });

  test('device falla → cloud entra como RESPALDO (no se queda en silencio)',
      () async {
    final mock = MockClient(
        (_) async => http.Response.bytes([1, 2, 3], 200));
    final rep = _FakeReproductor();
    final voz = _VozFake(ok: false);
    final tts = TtsService(inner: mock, reproductor: rep, vozDispositivo: voz);

    var ok = 0, fallo = 0, cloud = 0;
    tts.narrarRapido(
      'hola',
      onFallo: () => fallo++,
      onDispositivo: () => ok++,
      onCloud: () => cloud++,
    );
    await _tick();

    expect(voz.hablo, 1);
    expect(rep.reproducirCount, 1); // SÍ sonó por cloud
    expect(ok, 0);
    expect(cloud, 1);
    expect(fallo, 0);
    expect(tts.ultimoEvento?.proveedor, ProveedorTts.cloud);
    expect(tts.ultimoEvento?.exito, isTrue);
    expect(tts.ultimoEvento?.motivo, 'respaldo');
    await tts.dispose();
  });

  test('ambos fallan → onFallo (texto, sin voz)', () async {
    final mock = MockClient(
        (_) async => http.Response('caido', 503));
    final rep = _FakeReproductor();
    final voz = _VozFake(ok: false);
    final tts = TtsService(inner: mock, reproductor: rep, vozDispositivo: voz);

    var ok = 0, fallo = 0, cloud = 0;
    tts.narrarRapido(
      'hola',
      onFallo: () => fallo++,
      onDispositivo: () => ok++,
      onCloud: () => cloud++,
    );
    // 3 intentos del cloud con backoff (~250+500ms) → esperamos un poco.
    await _tick(1200);

    expect(voz.hablo, 1);
    expect(rep.reproducirCount, 0);
    expect(ok, 0);
    expect(cloud, 0);
    expect(fallo, 1);
    expect(tts.ultimoEvento?.proveedor, ProveedorTts.cloud);
    expect(tts.ultimoEvento?.exito, isFalse);
    await tts.dispose();
  });

  test('una nueva narración INTERRUMPE la previa (detiene rep + voz)',
      () async {
    final mock = MockClient(
        (_) async => http.Response.bytes([1, 2, 3], 200));
    final rep = _FakeReproductor();
    final voz = _VozFake(); // device habla siempre
    final tts = TtsService(inner: mock, reproductor: rep, vozDispositivo: voz);

    tts.narrarRapido('uno');
    await _tick(5);
    tts.narrarRapido('dos');
    await _tick(50);

    // La segunda llamada DEBE haber detenido la voz previa y arrancado de
    // nuevo: sirve para evitar pegado de frases viejas en la cámara.
    expect(voz.hablo, 2);
    expect(voz.detenido, greaterThanOrEqualTo(2));
    await tts.dispose();
  });

  test('prepararDispositivo delega a la voz (eager init)', () async {
    final mock = MockClient((_) async => http.Response.bytes([1], 200));
    final voz = _VozFake();
    final tts = TtsService(
        inner: mock, reproductor: _FakeReproductor(), vozDispositivo: voz);

    final ok = await tts.prepararDispositivo();
    expect(ok, isTrue);
    expect(voz.preparado, 1);
    expect(tts.idiomaDispositivo, 'es-419');
    await tts.dispose();
  });
}
