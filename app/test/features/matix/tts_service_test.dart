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

/// Devuelve los códigos de la lista en orden (repite el último). Cuenta los
/// hits para verificar reintentos.
http.Client _mockSecuencia(List<int> codigos, {void Function()? alPedir}) {
  var i = 0;
  return MockClient((req) async {
    alPedir?.call();
    final code = i < codigos.length ? codigos[i] : codigos.last;
    i++;
    if (code == 200) return http.Response.bytes([1, 2, 3], 200);
    return http.Response('boom', code);
  });
}

/// Voz del dispositivo fake: el `hablar` device-first la usa primero.
class _VozFake implements VozDispositivo {
  _VozFake({this.ok = true});
  bool ok;
  int hableYEspere = 0;
  @override
  Future<bool> hablar(String texto) async => ok;
  @override
  Future<bool> hablarYEsperar(String texto) async {
    hableYEspere++;
    return ok;
  }

  @override
  Future<void> detener() async {}
  @override
  Future<bool> preparar() async => ok;
  @override
  String? get idiomaActivo => ok ? 'es-419' : null;
}

Future<void> _tick() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  test('hablar: DEVICE-FIRST — habla por el dispositivo, onInicio dispara, '
      'sin cloud', () async {
    final rep = _FakeReproductor();
    final voz = _VozFake(ok: true);
    final tts = TtsService(inner: _mockMp3(), reproductor: rep, vozDispositivo: voz);
    var sono = false;

    await tts.hablar('hola', onInicio: () => sono = true);

    expect(voz.hableYEspere, 1); // habló el dispositivo
    expect(sono, isTrue); // onInicio se notificó
    expect(rep.reproducirCount, 0); // NO sonó el cloud
    expect(tts.ultimoEvento?.proveedor, ProveedorTts.dispositivo);
  });

  test('detener: corta el audio y resuelve el hablar en curso (juntos)',
      () async {
    final rep = _FakeReproductor();
    // Device falla → hablar cae al cloud; detener corta esa reproducción.
    final voz = _VozFake(ok: false);
    final tts = TtsService(inner: _mockMp3(), reproductor: rep, vozDispositivo: voz);

    final fut = tts.hablar('hola');
    await _tick();
    rep.sonar();
    await _tick();

    await tts.detener();
    expect(rep.detenerCount, greaterThanOrEqualTo(1)); // audio cortado
    await fut; // la espera de hablar se resolvió (no queda colgada)
  });

  test('hablar reintenta ante un 502 transitorio y termina sonando', () async {
    final rep = _FakeReproductor();
    var pedidos = 0;
    final tts = TtsService(
      inner: _mockSecuencia([502, 200], alPedir: () => pedidos++),
      reproductor: rep,
    );
    final fut = tts.hablar('hola');
    // Backoff de 250ms tras el primer 502 + segunda descarga OK.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(pedidos, 2); // reintentó una vez
    expect(rep.reproducirCount, 1); // y reprodujo
    rep.sonar();
    rep.completar();
    await fut;
  });

  test('narrar reproduce en segundo plano sin esperar el fin', () async {
    final rep = _FakeReproductor();
    final tts = TtsService(inner: _mockMp3(), reproductor: rep);
    tts.narrar('hola'); // no se await-ea
    await _tick(); // descarga + reproducir
    expect(rep.reproducirCount, 1);
    // No necesita completar() para "terminar": es fire-and-forget.
  });

  test('narrar: una descarga superada NO reproduce (última gana, sin cola)',
      () async {
    final rep = _FakeReproductor();
    // La descarga de "viejo" tarda; la de "nuevo" es instantánea.
    final inner = MockClient((req) async {
      if (req.body.contains('viejo')) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      return http.Response.bytes([1, 2, 3], 200);
    });
    final tts = TtsService(inner: inner, reproductor: rep);

    tts.narrar('viejo'); // arranca su descarga lenta
    tts.narrar('nuevo'); // la supera de inmediato

    // Espera a que AMBAS descargas resuelvan.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    // Solo la última ("nuevo") sonó; la vieja, al volver tarde, se descartó.
    expect(rep.reproducirCount, 1);
  });

  test('detener invalida una descarga en vuelo (no suena tras parar)', () async {
    final rep = _FakeReproductor();
    final inner = MockClient((req) async {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      return http.Response.bytes([1, 2, 3], 200);
    });
    final tts = TtsService(inner: inner, reproductor: rep);

    tts.narrar('algo'); // descarga lenta en vuelo
    await tts.detener(); // paramos ANTES de que termine la descarga
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(rep.reproducirCount, 0); // la descarga tardía ya no reproduce
  });

  test('narrar NUNCA lanza y avisa onFallo si la voz no sale (502 persistente)',
      () async {
    final rep = _FakeReproductor();
    final tts = TtsService(inner: _mockSecuencia([502]), reproductor: rep);
    var fallo = false;
    // No lanza, aunque el TTS devuelva 502 siempre.
    tts.narrar('hola', onFallo: () => fallo = true);
    // 3 intentos con backoff 250ms + 500ms.
    await Future<void>.delayed(const Duration(milliseconds: 950));
    expect(fallo, isTrue);
    expect(rep.reproducirCount, 0); // nunca sonó
  });
}
