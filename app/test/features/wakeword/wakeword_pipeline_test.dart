import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/wakeword/data/wakeword_pipeline.dart';

/// Backend fake determinista: ignora el audio real y devuelve frames/embeddings
/// constantes; la probabilidad la fija el test. Así probamos SOLO la
/// fontanería de buffers/ventaneo/umbral/refractario (los ONNX nativos no
/// corren en flutter test).
class _FakeBackend implements WakeWordBackend {
  _FakeBackend({required this.score});
  double score;
  int clasifCalls = 0;
  int embCalls = 0;

  @override
  Future<void> cargar({void Function(String paso)? migaja}) async {}

  @override
  Future<List<Float32List>> melspectrograma(Float32List muestras) async {
    // 8 frames por bloque, como openWakeWord (≈80 ms).
    return List.generate(8, (_) => Float32List(WakeWordPipeline.kBinsMel));
  }

  @override
  Future<Float32List> embedding(List<Float32List> ventana76) async {
    embCalls++;
    expect(ventana76.length, WakeWordPipeline.kVentanaMel); // siempre 76
    return Float32List(96);
  }

  @override
  Future<double> clasificar(List<Float32List> ventana16) async {
    clasifCalls++;
    expect(ventana16.length, WakeWordPipeline.kVentanaFeatures); // siempre 16
    return score;
  }

  @override
  Future<void> liberar() async {}
}

/// Un bloque de 1280 muestras PCM16 = 2560 bytes (silencio; el fake los ignora).
Uint8List _bloque() => Uint8List(WakeWordPipeline.kMuestrasBloque * 2);

void main() {
  test('no clasifica hasta tener 16 embeddings (warmup ~1.3 s)', () async {
    final fake = _FakeBackend(score: 0.9);
    final p = WakeWordPipeline(fake, umbral: 0.5);
    var dets = 0;
    // 15 bloques → 15 embeddings, aún por debajo de la ventana de 16.
    for (var i = 0; i < 15; i++) {
      if (await p.alimentarPcm(_bloque())) dets++;
    }
    expect(fake.embCalls, 15); // un embedding por bloque
    expect(fake.clasifCalls, 0); // nunca clasificó: faltaban features
    expect(dets, 0);
  });

  test('dispara una vez al cruzar el umbral y entra en refractario', () async {
    final fake = _FakeBackend(score: 0.9);
    final p = WakeWordPipeline(fake, umbral: 0.5, refractarioFrames: 16);
    var dets = 0;
    // 16 bloques → en el 16º hay 16 features → clasifica → 0.9 ≥ 0.5 → dispara.
    for (var i = 0; i < 16; i++) {
      if (await p.alimentarPcm(_bloque())) dets++;
    }
    expect(dets, 1);
    expect(fake.clasifCalls, 1);

    // En refractario: 15 bloques más, sin nuevas detecciones ni nuevas
    // clasificaciones (no re-dispara con la misma cola de audio).
    for (var i = 0; i < 15; i++) {
      if (await p.alimentarPcm(_bloque())) dets++;
    }
    expect(dets, 1);
    expect(fake.clasifCalls, 1);
  });

  test('bajo el umbral nunca dispara, aunque clasifique', () async {
    final fake = _FakeBackend(score: 0.2);
    final p = WakeWordPipeline(fake, umbral: 0.5);
    var dets = 0;
    for (var i = 0; i < 40; i++) {
      if (await p.alimentarPcm(_bloque())) dets++;
    }
    expect(dets, 0);
    expect(fake.clasifCalls, greaterThan(0)); // sí evaluó, pero nunca cruzó
  });

  test('reiniciar limpia el estado (relevo de micro)', () async {
    final fake = _FakeBackend(score: 0.9);
    final p = WakeWordPipeline(fake, umbral: 0.5);
    for (var i = 0; i < 10; i++) {
      await p.alimentarPcm(_bloque());
    }
    p.reiniciar();
    fake.clasifCalls = 0;
    fake.embCalls = 0;
    // Tras reiniciar, vuelve a necesitar el warmup completo.
    var dets = 0;
    for (var i = 0; i < 15; i++) {
      if (await p.alimentarPcm(_bloque())) dets++;
    }
    expect(fake.clasifCalls, 0);
    expect(dets, 0);
  });

  test('acumula bytes parciales hasta completar un bloque', () async {
    final fake = _FakeBackend(score: 0.9);
    final p = WakeWordPipeline(fake, umbral: 0.5);
    // Medio bloque: no debe procesar nada todavía.
    await p.alimentarPcm(Uint8List(WakeWordPipeline.kMuestrasBloque));
    expect(fake.embCalls, 0);
    // La otra mitad completa el primer bloque → un embedding.
    await p.alimentarPcm(Uint8List(WakeWordPipeline.kMuestrasBloque));
    expect(fake.embCalls, 1);
  });
}
