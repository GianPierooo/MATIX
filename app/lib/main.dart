import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'api/matix_client.dart';
import 'core/notificaciones_service.dart';
import 'core/providers.dart';
import 'features/briefing/presentation/briefing_screen.dart';
import 'features/cierre/presentation/cierre_screen.dart';
import 'features/eventos/presentation/nuevo_evento_screen.dart';
import 'features/eventos/providers/eventos_providers.dart';
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

  /// Llave del Navigator para que callbacks que viven fuera del
  /// widget tree (handler de notificaciones, deep links) puedan
  /// empujar pantallas. Se la pasamos al MaterialApp.
  final GlobalKey<NavigatorState> _navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Registrar el handler de tap de notificaciones: si el payload
    // es 'briefing', abrimos la pantalla del briefing. Capa 8
    // reducida · Paso 1.
    final notis = ref.read(notificacionesServiceProvider);
    notis.registrarOnTap((payload) {
      if (payload == 'briefing') {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const BriefingScreen()),
        );
      } else if (payload == 'cierre') {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const CierreScreen()),
        );
      } else if (payload != null && payload.startsWith('evento:')) {
        // Recordatorio de evento (Cal-2): abrimos su detalle/edición.
        // El detalle es la propia pantalla de edición.
        unawaited(_abrirEvento(payload.substring('evento:'.length)));
      }
    });
    // Aseguramos la inicialización (carga timezones + plugin). Si
    // el usuario ya tiene la noti del briefing activa, el config
    // controller la reprograma al leer SharedPreferences.
    unawaited(notis.inicializar());
  }

  /// Trae el evento por id y abre su pantalla de edición (que hace de
  /// detalle). Si la red falla, no abrimos nada — mejor mudo que crash.
  Future<void> _abrirEvento(String id) async {
    try {
      final evento = await ref.read(eventosRepositoryProvider).obtener(id);
      _navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => NuevoEventoScreen(evento: evento)),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Deep link evento falló: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Matix',
      debugShowCheckedModeBanner: false,
      theme: buildMatixTheme(),
      home: ConfigBanner(child: HomeShell(client: _client)),
    );
  }
}
