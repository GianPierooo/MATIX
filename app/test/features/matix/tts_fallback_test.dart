import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matix/features/matix/data/tts_service.dart';

/// Cadena de respaldo de la voz: si la TTS en la nube (cerebro) falla, la app
/// habla con la voz NATIVA del dispositivo; solo si el dispositivo TAMPOCO
/// puede, se queda en texto. Aquí se prueba con fakes (sin red ni audio real).

class _RepFake implements ReproductorAudio {
  @override
  Future<void> reproducir(List<int> mp3) async {}
  @override
  Future<void> detener() async {}
  @override
  Stream<bool> get reproduciendo => const Stream<bool>.empty();
  @override
  Stream<void> get alCompletar => const Stream<void>.empty();
  @override
  Future<void> liberar() async {}
}

class _VozFake implements VozDispositivo {
  _VozFake(this.ok);
  final bool ok;
  final String? idioma = 'es-419';
  int veces = 0;
  int detenciones = 0;
  bool preparado = false;
  @override
  Future<bool> hablar(String texto) async {
    veces++;
    return ok;
  }

  @override
  Future<bool> hablarYEsperar(String texto) async {
    veces++;
    return ok;
  }

  @override
  Future<void> detener() async {
    detenciones++;
  }

  @override
  Future<bool> preparar() async {
    preparado = true;
    return ok;
  }

  @override
  String? get idiomaActivo => preparado ? idioma : null;
}

void main() {
  test('narrar cae a la voz del dispositivo cuando el cloud TTS falla', () async {
    final mock = MockClient((_) async => http.Response('caido', 503));
    final voz = _VozFake(true);
    var dispositivo = 0;
    var fallo = 0;
    final tts = TtsService(inner: mock, reproductor: _RepFake(), vozDispositivo: voz);

    tts.narrar('hola', onFallo: () => fallo++, onDispositivo: () => dispositivo++);
    await Future<void>.delayed(const Duration(seconds: 2));

    expect(voz.veces, 1); // habló el dispositivo
    expect(dispositivo, 1); // se avisó "voz del teléfono"
    expect(fallo, 0); // NO se quedó en texto
    await tts.dispose();
  });

  test('narrar cae a texto solo si NI el dispositivo puede hablar', () async {
    final mock = MockClient((_) async => http.Response('caido', 503));
    final voz = _VozFake(false); // el dispositivo tampoco habla
    var dispositivo = 0;
    var fallo = 0;
    final tts = TtsService(inner: mock, reproductor: _RepFake(), vozDispositivo: voz);

    tts.narrar('hola', onFallo: () => fallo++, onDispositivo: () => dispositivo++);
    await Future<void>.delayed(const Duration(seconds: 2));

    expect(fallo, 1); // último recurso: texto
    expect(dispositivo, 0);
    await tts.dispose();
  });
}
