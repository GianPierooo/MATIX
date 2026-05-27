import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'api/matix_client.dart';
import 'core/providers.dart';
import 'screens/home_shell.dart';
import 'theme/matix_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Sin esto, `DateFormat('...', 'es')` lanza LocaleDataException en
  // dispositivos que no traen pre-cargado el locale español.
  await initializeDateFormatting('es', null);

  // Firebase: solo `core`. Con `google-services.json` en
  // android/app/, `Firebase.initializeApp()` lee la config nativa
  // sin necesidad de pasar `options:`. Esto sirve para que el APK
  // quede asociado al proyecto Firebase y App Distribution lo
  // distribuya correctamente (la app "App Tester" del teléfono
  // identifica builds por appId, no necesita la inicialización
  // para entregar notificaciones, pero la dejamos lista para futuras
  // funciones como Crashlytics o push).
  //
  // Si el `google-services.json` no está embebido (checkout limpio
  // sin Firebase configurado), `initializeApp` falla. Lo atrapamos
  // y seguimos — la app funciona sin Firebase, solo perdemos la
  // capacidad de usar servicios Firebase.
  try {
    await Firebase.initializeApp();
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Firebase no inicializado (sin google-services.json): $e');
    }
  }

  runApp(const ProviderScope(child: MatixApp()));
}

class MatixApp extends ConsumerStatefulWidget {
  const MatixApp({super.key});
  @override
  ConsumerState<MatixApp> createState() => _MatixAppState();
}

class _MatixAppState extends ConsumerState<MatixApp> {
  late final MatixClient _client = ref.read(matixClientProvider);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Matix',
      debugShowCheckedModeBanner: false,
      theme: buildMatixTheme(),
      home: ConfigBanner(child: HomeShell(client: _client)),
    );
  }
}
