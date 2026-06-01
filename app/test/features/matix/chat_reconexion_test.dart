import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matix/api/matix_client.dart';
import 'package:matix/core/providers.dart';
import 'package:matix/features/matix/data/matix_chat_repository.dart';
import 'package:matix/features/matix/domain/mensaje.dart';
import 'package:matix/features/matix/providers/matix_chat_providers.dart';

/// Repo de chat fake: la PRIMERA llamada simula una caída transitoria
/// (connection abort = statusCode 0); la SEGUNDA (el reintento) devuelve el
/// resultado. Registra la `idempotencyKey` de cada llamada.
class _FakeChatRepo implements MatixChatRepository {
  final List<String?> keys = [];
  int _n = 0;

  @override
  Future<ChatTurno> enviar({
    required List<Mensaje> historial,
    required String mensaje,
    List<String> imagenes = const [],
    String? documentoNombre,
    String? documentoTexto,
    String? idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    _n++;
    if (_n == 1) {
      throw MatixApiException(0, 'Software caused connection abort');
    }
    return const ChatTurno(
      respuesta: 'Recuperado tras reconectar',
      toolsUsadas: <String>[],
      tablasCambiadas: <String>[],
    );
  }
}

void main() {
  ProviderContainer hacerContainer(_FakeChatRepo fake) {
    // MockClient para que el load de modos (en el path de éxito) resuelva sin
    // red ni timers reales.
    final mock = MockClient((req) async {
      if (req.url.path.endsWith('/modos')) {
        return http.Response('{"disponibles":[],"activo":null}', 200);
      }
      return http.Response('{}', 200);
    });
    final c = ProviderContainer(overrides: [
      matixChatRepositoryProvider.overrideWithValue(fake),
      matixClientProvider.overrideWithValue(MatixClient(inner: mock)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('caída transitoria → reconectando suave (no error rojo) + mensaje queda',
      () async {
    final fake = _FakeChatRepo();
    final c = hacerContainer(fake);
    final notifier = c.read(chatMatixProvider.notifier);

    await notifier.enviar('regístrame un gasto de 30');

    final s = c.read(chatMatixProvider);
    expect(s.reconectando, isTrue); // aviso suave
    expect(s.errorUltimoEnvio, isNull); // NO error rojo
    // El mensaje del usuario no se pierde.
    expect(s.mensajes.last.contenido, 'regístrame un gasto de 30');
    expect(s.mensajes.last.rol, RolMensaje.usuario);
  });

  test('al reconectar re-sincroniza con la MISMA clave (idempotente)',
      () async {
    final fake = _FakeChatRepo();
    final c = hacerContainer(fake);
    final notifier = c.read(chatMatixProvider.notifier);

    await notifier.enviar('regístrame un gasto de 30'); // 1ra: cae
    expect(c.read(chatMatixProvider).reconectando, isTrue);

    // Volver a la app / botón reintentar → 2da llamada: éxito.
    notifier.reconectarAhora();
    await pumpEventQueue();

    final s = c.read(chatMatixProvider);
    expect(s.reconectando, isFalse);
    expect(s.errorUltimoEnvio, isNull);
    // Re-sincronizó: la respuesta que se había perdido en vuelo aparece.
    expect(s.mensajes.last.contenido, 'Recuperado tras reconectar');
    expect(s.mensajes.last.rol, RolMensaje.matix);

    // CLAVE: el reintento usó la MISMA idempotency_key (→ el cerebro no
    // duplica el gasto).
    expect(fake.keys.length, 2);
    expect(fake.keys[0], isNotNull);
    expect(fake.keys[0], fake.keys[1]);
  });
}
