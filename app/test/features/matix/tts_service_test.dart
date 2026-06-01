import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matix/features/matix/data/tts_service.dart';

/// Reproductor fake controlable: el test decide cuándo "suena" y cuándo
/// "termina", para verificar el estado de reproducción.
class _FakeReproductor implements ReproductorAudio {
  final _rep = StreamController<bool>.broadcast();
  final _fin = StreamController<void>.broadcast();
  int reproducirCount = 0;
  int detenerCount = 0;

  @override
  Future<void> reproducir(List<int> mp3) async => reproducirCount++;

  @override
  Future<void> detener() async {
    detenerCount++;
    _rep.add(false); // el reproductor real también deja de estar "playing"
  }

  @override
  Stream<bool> get reproduciendo => _rep.stream;

  @override
  Stream<void> get alCompletar => _fin.stream;

  @override
  Future<void> liberar() async {
    await _rep.close();
    await _fin.close();
  }

  void sonar() => _rep.add(true);
  void completar() => _fin.add(null);
}

http.Client _mockMp3() =>
    MockClient((req) async => http.Response.bytes([1, 2, 3], 200));

Future<void> _tick() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  test('hablar: onInicio dispara al SONAR (no al descargar) y resuelve al fin',
      () async {
    final rep = _FakeReproductor();
    final tts = TtsService(inner: _mockMp3(), reproductor: rep);
    var sono = false;
    var termino = false;

    final fut = tts.hablar('hola', onInicio: () => sono = true)
      ..then((_) => termino = true);

    await _tick(); // descarga + reproducir
    expect(rep.reproducirCount, 1);
    expect(sono, isFalse); // descargó pero aún no suena → sin desfase

    rep.sonar();
    await _tick();
    expect(sono, isTrue); // el visual arranca acá, junto al audio
    expect(termino, isFalse);

    rep.completar();
    await fut;
    expect(termino, isTrue);
  });

  test('detener: corta el audio y resuelve el hablar en curso (juntos)',
      () async {
    final rep = _FakeReproductor();
    final tts = TtsService(inner: _mockMp3(), reproductor: rep);

    final fut = tts.hablar('hola');
    await _tick();
    rep.sonar();
    await _tick();

    await tts.detener();
    expect(rep.detenerCount, greaterThanOrEqualTo(1)); // audio cortado
    await fut; // la espera de hablar se resolvió (no queda colgada)
  });
}
