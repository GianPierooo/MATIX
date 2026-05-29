import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matix/features/autoupdate/data/update_service.dart';
import 'package:matix/features/autoupdate/presentation/update_dialog.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Tests del diálogo de auto-actualización (vía navegador).
///
/// El bug que arreglamos: `ota_update` instalaba in-app y crasheaba
/// de forma nativa en el Huawei sin Google Play Services (FileProvider
/// no declarado → excepción no atrapada en el main looper). Ahora el
/// diálogo abre el APK en el navegador del sistema con `launchUrl` en
/// modo `externalApplication`. Estos tests fijan ese contrato:
///
/// - Tocar "Descargar e instalar" llama `launchUrl` con el `apkUrl`
///   exacto y modo `externalApplication`.
/// - Si el navegador abre, la UI pasa a la fase "abierto" con las
///   instrucciones para terminar la instalación.
/// - Si `launchUrl` falla (devuelve false o lanza), la UI muestra el
///   error y el enlace copiable — nunca muere en silencio.

class _FakeUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<String> urls = [];
  PreferredLaunchMode? ultimoModo;

  /// Qué devuelve `launchUrl`. Si `lanzaError` es true, tira en su
  /// lugar (simula el navegador que no abre en EMUI).
  bool resultado = true;
  bool lanzaError = false;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    urls.add(url);
    ultimoModo = options.mode;
    if (lanzaError) {
      throw Exception('No se pudo abrir el navegador (EMUI)');
    }
    return resultado;
  }
}

const _info = UpdateDisponible(
  version: '1.2.0',
  buildNumber: 14,
  apkUrl: 'https://supabase.example/storage/v1/object/public/apks/matix-14.apk',
  notas: 'Arreglo del auto-update en Huawei.',
);

void main() {
  late _FakeUrlLauncher fake;

  setUp(() {
    fake = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = fake;
  });

  Future<void> abrirDialogo(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => mostrarUpdateDialog(
                  context,
                  info: _info,
                  buildLocal: 13,
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('toca instalar → launchUrl con apkUrl y externalApplication',
      (tester) async {
    await abrirDialogo(tester);

    await tester.tap(find.text('Descargar e instalar'));
    await tester.pumpAndSettle();

    expect(fake.urls, [_info.apkUrl]);
    expect(fake.ultimoModo, PreferredLaunchMode.externalApplication);
  });

  testWidgets('navegador abre → fase "abierto" con instrucciones',
      (tester) async {
    fake.resultado = true;
    await abrirDialogo(tester);

    await tester.tap(find.text('Descargar e instalar'));
    await tester.pumpAndSettle();

    expect(find.text('Descarga abierta en el navegador'), findsOneWidget);
    expect(find.text('Listo'), findsOneWidget);
  });

  testWidgets('launchUrl devuelve false → fase error con enlace copiable',
      (tester) async {
    fake.resultado = false;
    await abrirDialogo(tester);

    await tester.tap(find.text('Descargar e instalar'));
    await tester.pumpAndSettle();

    // El enlace queda visible (SelectableText) y hay Reintentar.
    expect(find.text(_info.apkUrl), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('launchUrl lanza → fase error, no propaga el crash',
      (tester) async {
    fake.lanzaError = true;
    await abrirDialogo(tester);

    await tester.tap(find.text('Descargar e instalar'));
    await tester.pumpAndSettle();

    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.textContaining('No pude abrir el navegador'), findsOneWidget);
    // No quedó ninguna excepción sin atrapar.
    expect(tester.takeException(), isNull);
  });

  testWidgets('copiar enlace copia el apkUrl y muestra confirmación',
      (tester) async {
    // Capturamos lo que se manda al portapapeles vía el method channel
    // del sistema (determinístico, sin depender del fake de clipboard).
    String? copiado;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiado = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    fake.resultado = true;
    await abrirDialogo(tester);
    await tester.tap(find.text('Descargar e instalar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Copiar enlace'));
    await tester.pumpAndSettle();

    expect(copiado, _info.apkUrl);
    expect(find.text('Enlace copiado al portapapeles'), findsOneWidget);
  });
}
