import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matix/features/matix/data/tts_service.dart';

/// `TtsService.hablar` (chat / manos libres / briefing / cierre) ahora es
/// DEVICE-FIRST: la voz de Matix es la del dispositivo; el cloud (OpenAI) solo
/// entra como ÚLTIMO recurso si el device falla por completo.

class _RepFake implements ReproductorAudio {
  int reproducir_ = 0;
  @override
  Future<void> reproducir(List<int> mp3) async => reproducir_++;
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
  _VozFake({this.ok = true});
  bool ok;
  int hablo = 0;
  int hableYEspere = 0;
  int detenido = 0;
  @override
  Future<bool> hablar(String texto) async {
    hablo++;
    return ok;
  }

  @override
  Future<bool> hablarYEsperar(String texto) async {
    hableYEspere++;
    return ok;
  }

  @override
  Future<void> detener() async {
    detenido++;
  }

  @override
  Future<bool> preparar() async => ok;
  @override
  String? get idiomaActivo => ok ? 'es-419' : null;
}

void main() {
  test('hablar usa el DISPOSITIVO primero; NO toca el cloud', () async {
    var huboHttp = 0;
    final mock = MockClient((_) async {
      huboHttp++;
      return http.Response.bytes([1, 2, 3], 200);
    });
    final voz = _VozFake(ok: true);
    final rep = _RepFake();
    final tts = TtsService(inner: mock, reproductor: rep, vozDispositivo: voz);

    var inicio = 0;
    await tts.hablar('hola', onInicio: () => inicio++);

    expect(voz.hableYEspere, 1); // habló el dispositivo, esperando el fin
    expect(huboHttp, 0); // NO se llamó al cloud
    expect(rep.reproducir_, 0); // NO sonó mp3 del cloud
    expect(inicio, 1); // onInicio se notificó
    expect(tts.ultimoEvento?.proveedor, ProveedorTts.dispositivo);
    expect(tts.ultimoEvento?.exito, isTrue);
    await tts.dispose();
  });

  test('si el dispositivo falla, cae al cloud como ÚLTIMO recurso', () async {
    var huboHttp = 0;
    final mock = MockClient((_) async {
      huboHttp++;
      return http.Response.bytes([1, 2, 3], 200);
    });
    final voz = _VozFake(ok: false); // el device no habla
    final rep = _RepFake();
    final tts = TtsService(inner: mock, reproductor: rep, vozDispositivo: voz);

    // El completer del cloud se resuelve por el stream alCompletar (vacío en el
    // fake) → lo cerramos con detener tras un microtask para no colgar el test.
    final fut = tts.hablar('hola');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tts.detener(); // resuelve el completer del cloud
    await fut;

    expect(voz.hableYEspere, 1); // se intentó el device
    expect(huboHttp, 1); // SÍ se pidió al cloud (último recurso)
    expect(rep.reproducir_, 1); // sonó el mp3 del cloud
    await tts.dispose();
  });
}
