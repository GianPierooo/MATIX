import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'api/matix_client.dart';
import 'core/notificaciones_service.dart';
import 'core/providers.dart';
import 'features/apuntes/presentation/editor_apunte_screen.dart';
import 'features/apuntes/providers/apuntes_providers.dart';
import 'features/briefing/presentation/briefing_screen.dart';
import 'features/cierre/presentation/cierre_screen.dart';
import 'features/repaso/presentation/repaso_semanal_screen.dart';
import 'features/compartir/data/share_intent_service.dart';
import 'features/eventos/presentation/nuevo_evento_screen.dart';
import 'features/eventos/providers/eventos_providers.dart';
import 'features/matix/data/captura_apunte_repository.dart';
import 'features/matix/presentation/manos_libres_screen.dart';
import 'features/matix/providers/captura_apunte_providers.dart';
import 'features/matix/providers/navegacion_matix_provider.dart';
import 'features/proyectos/presentation/detalle_proyecto_screen.dart';
import 'features/push/application/push_service.dart';
import 'features/wakeword/data/wakeword_log.dart';
import 'features/wakeword/providers/wakeword_providers.dart';
import 'features/tareas/presentation/nueva_tarea_screen.dart';
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
    // Push (FCM · Capa 1): el handler de background DEBE registrarse antes
    // de runApp y apuntar a una función top-level. Los OEM matan las
    // notifs locales en segundo plano; el push las reemplaza.
    FirebaseMessaging.onBackgroundMessage(manejarPushEnBackground);
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

class _MatixAppState extends ConsumerState<MatixApp>
    with WidgetsBindingObserver {
  late final MatixClient _client = ref.read(matixClientProvider);

  /// Llave del Navigator para que callbacks que viven fuera del
  /// widget tree (handler de notificaciones, deep links, compartir)
  /// puedan empujar pantallas. Se la pasamos al MaterialApp.
  final GlobalKey<NavigatorState> _navigatorKey =
      GlobalKey<NavigatorState>();

  /// Llave del ScaffoldMessenger para mostrar snackbars desde fuera del
  /// widget tree (ej. el feedback de "Compartir-a-Matix").
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// ¿Ya hay una pantalla de manos libres en el stack? Evita APILAR varias al
  /// decir "oye matix" varias veces seguidas. Se pone en true (síncrono) al
  /// empujarla y vuelve a false cuando se cierra (`.then` del push).
  bool _manosLibresEnStack = false;

  @override
  void initState() {
    super.initState();
    // Registrar el handler de tap de notificaciones: si el payload
    // es 'briefing', abrimos la pantalla del briefing. Capa 8
    // reducida · Paso 1.
    final notis = ref.read(notificacionesServiceProvider);
    // Mismo enrutado para el tap de una notificación local y para el de un
    // push de FCM (que trae el deep link en `data['payload']`).
    notis.registrarOnTap(_enrutarPayload);
    // Aseguramos la inicialización (carga timezones + plugin). Si
    // el usuario ya tiene la noti del briefing activa, el config
    // controller la reprograma al leer SharedPreferences.
    unawaited(notis.inicializar());
    // Push (FCM · Capa 1): pide permiso, registra el token en el cerebro y
    // escucha mensajes. Best-effort.
    unawaited(ref.read(pushServiceProvider).inicializar());
    // Deep link de push (Capa 2): tocar un push (app en background/cerrada)
    // enruta al evento/tarea. El payload viaja en `data['payload']`.
    try {
      FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => _enrutarPayload(m.data['payload'] as String?),
      );
      FirebaseMessaging.instance.getInitialMessage().then((m) {
        if (m != null) _enrutarPayload(m.data['payload'] as String?);
      });
    } catch (_) {
      // Firebase no inicializado (checkout sin google-services.json): sin
      // deep link de push, la app sigue.
    }
    // Refresca la ventana móvil de recordatorios de eventos (Cal-3):
    // las series recurrentes solo tienen agendados los próximos ~30
    // días, así que al abrir la app reagendamos para que la ventana
    // avance. Best-effort: si no hay red, la próxima apertura reintenta.
    unawaited(
      ref.read(eventosRepositoryProvider).refrescarVentanaRecordatorios(),
    );

    // Compartir-a-Matix (Capa 7): escuchamos lo que se comparte a la
    // app abierta, y revisamos si la app fue ABIERTA por un compartido.
    final share = ref.read(shareIntentServiceProvider);
    share.escuchar(_capturarCompartido);
    unawaited(_capturarCompartidoInicial(share));

    // Wake word "oye Matix" (Capa 2 · paso 1: tubería con modelo de prueba).
    // Solo escucha con la app en primer plano (v1), por eso lo colgamos del
    // ciclo de vida. Al detectar la palabra abrimos el modo manos libres
    // (mismo flujo que tocar para hablar).
    WidgetsBinding.instance.addObserver(this);
    // Blindaje del de-dup: cuando manos libres se cierra de verdad
    // (modoVozActivo→false), liberamos el flag SIEMPRE — así nunca queda en true
    // bloqueando un lanzamiento legítimo de "oye matix" (el guard solo debe
    // evitar APILAR, jamás frenar el primer/único launch).
    ref.listenManual<bool>(modoVozActivoProvider, (_, activo) {
      if (!activo) _manosLibresEnStack = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final wake = ref.read(wakeWordControllerProvider.notifier);
      wake.registrarAlDetectar(_abrirManosLibresPorWakeWord);
      // La app arranca en primer plano: si el usuario dejó la palabra activa,
      // empieza a escuchar (pide permiso solo si hace falta).
      unawaited(wake.alFrente());

      // Wake word en SEGUNDO PLANO (foreground service nativo). Si la app la
      // lanzó el service al detectar (full-screen intent), abrimos manos
      // libres; y registramos el callback para cuando detecte con la app ya
      // viva en background. El ARRANQUE/PARADA del service lo decide el
      // controller (motor in-app vs nativo según "segundo plano"); aquí solo
      // cableamos la apertura por detección.
      final bg = ref.read(wakeWordBgServiceProvider);
      bg.registrarAlAbrir(_abrirManosLibresPorWakeWord);
      unawaited(() async {
        if (await bg.consumirApertura()) {
          _abrirManosLibresPorWakeWord();
        }
      }());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    final wake = ref.read(wakeWordControllerProvider.notifier);
    if (estado == AppLifecycleState.resumed) {
      // Volvimos al frente. El controller decide el motor:
      // - "segundo plano" ON  → asegura el FGS nativo vivo (lo (re)lanza DESDE
      //   primer plano, estado elegible en Android 14+). No lo paramos en un
      //   `resumed` espurio: eso era lo que lo mataba a los 0 s.
      // - "segundo plano" OFF → pipeline in-app.
      unawaited(wake.alFrente());
    } else if (estado == AppLifecycleState.paused ||
        estado == AppLifecycleState.detached) {
      // A segundo plano. Con "segundo plano" ON el FGS YA está corriendo y
      // sigue vivo (no se arranca desde aquí — un FGS de micrófono no puede
      // iniciarse en background). Con OFF, soltamos el micro del in-app.
      unawaited(wake.alFondo());
    }
  }

  /// Detectada la palabra: abre el modo manos libres. El escuchador ya soltó
  /// el micro; `ManosLibresScreen` lo mantiene en pausa mientras está abierto
  /// y lo retoma al cerrarse.
  void _abrirManosLibresPorWakeWord() {
    final nav = _navigatorKey.currentState;
    wlog('navegando a ManosLibresScreen (navigator disponible=${nav != null})');
    if (nav == null) {
      wlog('navigatorKey.currentState es null — no pude navegar');
      return;
    }
    // NO APILAR: si manos libres ya está abierto (por wake word o por el FAB),
    // reutilizamos esa instancia. Doble guarda: el flag síncrono `_manosLibres
    // EnStack` (evita la carrera de dos detecciones casi simultáneas) y
    // `modoVozActivo` (verdad del notifier: el modo voz ya tiene el micro). La
    // app ya viene al frente por el full-screen intent del service; basta no
    // empujar otra pantalla.
    if (_manosLibresEnStack || ref.read(modoVozActivoProvider)) {
      wlog('manos libres ya abierto — no apilo otra instancia');
      return;
    }
    _manosLibresEnStack = true;
    nav
        .push(
          MaterialPageRoute(
            builder: (_) => const ManosLibresScreen(porWakeWord: true),
          ),
        )
        .then((_) => _manosLibresEnStack = false);
  }

  /// Si la app arrancó porque el usuario compartió texto/URL a Matix
  /// con la app cerrada, captura ese contenido como apunte.
  Future<void> _capturarCompartidoInicial(ShareIntentService share) async {
    final texto = await share.obtenerTextoInicial();
    if (texto != null) await _capturarCompartido(texto);
  }

  /// Último compartido procesado, para deduplicar re-entregas.
  String? _ultimoCompartido;
  DateTime? _ultimoCompartidoEn;

  /// Guarda lo compartido (texto o URL) como apunte clasificado,
  /// reusando el flujo del Paso C (`/matix/capturar-apunte`). Da
  /// feedback de una línea; si algo falla, lo dice — nada en silencio.
  Future<void> _capturarCompartido(String texto) async {
    // Dedup: Android puede re-entregar el MISMO compartido (recreación
    // de la Activity, o las dos vías inicial + onNewIntent). Si llega el
    // mismo texto en una ventana corta, lo ignoramos: así no duplicamos
    // el apunte ni reabrimos el aviso (era lo que lo dejaba "pegado").
    final ahora = DateTime.now();
    if (_ultimoCompartido == texto &&
        _ultimoCompartidoEn != null &&
        ahora.difference(_ultimoCompartidoEn!) < const Duration(seconds: 30)) {
      return;
    }
    _ultimoCompartido = texto;
    _ultimoCompartidoEn = ahora;
    try {
      final apunte = await ref.read(capturaApunteRepoProvider).capturar(texto);
      // Refresca Apuntes (y el "Hoy" de Inicio) para que aparezca ya.
      ref.invalidate(apuntesListProvider);
      _mostrarGuardado(apunte);
    } on MatixApiException catch (e) {
      _mostrar('No pude guardar lo compartido: ${e.message}');
    } catch (e) {
      _mostrar('No pude guardar lo compartido: $e');
    }
  }

  void _mostrarGuardado(ApunteCapturado a) {
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          // Duración explícita: el aviso se cierra solo aunque no toques
          // "Abrir" (antes parecía quedarse pegado por las re-entregas
          // del compartido; ya deduplicadas).
          duration: const Duration(seconds: 5),
          content: Text(a.destinoLabel),
          action: SnackBarAction(
            label: 'Abrir',
            onPressed: () => _navigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (_) => EditorApunteScreen(apunteId: a.id),
              ),
            ),
          ),
        ),
      );
  }

  void _mostrar(String mensaje) {
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
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

  /// Enruta un payload de notificación/push a su pantalla. Lo comparten el
  /// tap de una notificación local y el de un push de FCM.
  void _enrutarPayload(String? payload) {
    if (payload == 'briefing') {
      _navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const BriefingScreen()),
      );
    } else if (payload == 'cierre') {
      _navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const CierreScreen()),
      );
    } else if (payload == 'repaso') {
      _navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const RepasoSemanalScreen()),
      );
    } else if (payload == 'hoy' || payload == 'set_dia') {
      // Proactividad (pre-libre / hueco) y el set del día abren Inicio, donde
      // el plan "Hoy" ofrece las sugerencias tocables (sin abrir el chat).
      ref.read(objetivoNavegacionProvider.notifier).state = SeccionMatix.inicio;
    } else if (payload != null && payload.startsWith('evento:')) {
      unawaited(_abrirEvento(payload.substring('evento:'.length)));
    } else if (payload != null && payload.startsWith('tarea:')) {
      _navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => NuevaTareaScreen(
            tareaId: payload.substring('tarea:'.length),
          ),
        ),
      );
    } else if (payload != null && payload.startsWith('proyecto:')) {
      // Proactividad (reposición): abre el proyecto, con su próxima acción y la
      // descomposición lista para arrancar.
      _navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => DetalleProyectoScreen(
            proyectoId: payload.substring('proyecto:'.length),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      title: 'Matix',
      debugShowCheckedModeBanner: false,
      theme: buildMatixTheme(),
      home: ConfigBanner(child: HomeShell(client: _client)),
    );
  }
}
