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
import 'features/horario/providers/horario_providers.dart';
import 'features/matix/data/captura_apunte_repository.dart';
import 'features/matix/data/tts_service.dart';
import 'features/matix/presentation/manos_libres_screen.dart';
import 'features/matix/providers/captura_apunte_providers.dart';
import 'features/matix/providers/manos_libres_providers.dart';
import 'features/matix/providers/navegacion_matix_provider.dart';
import 'features/proyectos/presentation/detalle_proyecto_screen.dart';
import 'features/push/application/push_service.dart';
import 'features/wakeword/data/wakeword_log.dart';
import 'features/wakeword/data/wakeword_prefs.dart';
import 'features/wakeword/domain/voz_overlay.dart';
import 'features/wakeword/providers/wakeword_providers.dart';
import 'features/tareas/presentation/nueva_tarea_screen.dart';
import 'features/widgets_inicio/data/widget_service.dart';
import 'features/widgets_inicio/domain/widget_datos.dart' show tareaIdDeCompletar;
import 'features/push/application/rendicion_cuentas_background.dart';
import 'core/hub_refresh.dart';
import 'screens/home_shell.dart';
import 'theme/matix_theme.dart';
import 'package:home_widget/home_widget.dart';

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

  /// ¿Hay una sesión de voz corriendo en el OVERLAY flotante (sin pantalla
  /// completa)? Evita duplicar y permite cerrar/relé de estado.
  bool _overlayActivo = false;
  ProviderSubscription<EstadoManosLibres>? _overlaySub;

  /// Último refresco de las notis proactivas — throttle para no machacar el
  /// endpoint en cada resume (la app entra y sale muchas veces seguidas).
  DateTime? _ultimoRefrescoNotisProactivas;

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
    // Voz de Matix: calienta el motor TTS del dispositivo al arrancar (carga el
    // idioma es-* y la voz/tono/velocidad de la config centralizada) para que
    // la PRIMERA vez que Matix hable no pague la latencia de configuración ni
    // falle. Best-effort: si el motor no está, la primera `hablar` lo prepara.
    unawaited(VozDispositivoFlutterTts().preparar());
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

    // Widgets de pantalla de inicio (Próximo/Hoy):
    //  - Empujamos el plan al widget cada vez que cambia (completar, saltar,
    //    replanificar, despertar, rollover invalidan `planDiaProvider` → al
    //    re-resolver, este listener empuja la versión fresca). Cubre también la
    //    primera carga. Fuente única: el plan determinista que ya calculamos.
    ref.listenManual<AsyncValue<dynamic>>(planDiaProvider, (_, next) {
      next.whenData((plan) => unawaited(
            WidgetService.actualizar(plan, DateTime.now()),
          ));
    }, fireImmediately: true);
    //  - Tap en un ítem del widget → deep link (abre Matix en la pantalla
    //    correspondiente). Reusa el mismo enrutado que las notificaciones.
    try {
      HomeWidget.widgetClicked.listen(_enrutarPayloadWidget);
      unawaited(
        HomeWidget.initiallyLaunchedFromHomeWidget().then(_enrutarPayloadWidget),
      );
    } catch (_) {
      // home_widget no disponible (p. ej. tests / plataforma): la app sigue.
    }
    //  - Refresco periódico en background (WorkManager, no agresivo).
    unawaited(WidgetService.registrarRefrescoPeriodico());

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
      // Wake en SEGUNDO PLANO (otra app adelante): decide overlay vs fullscreen.
      bg.registrarAlAbrir(_alWakeEnBackground);
      // Toques de la burbuja: "Abrir" → Matix completo; "Cerrar" → terminar.
      bg.registrarOverlay(alAbrir: _expandirOverlay, alCerrar: _cerrarOverlay);
      unawaited(() async {
        // La app la LANZÓ el wake (estaba cerrada) → fullscreen (no hay engine
        // vivo para overlay; degrada al comportamiento clásico).
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
      // Widget al frente: re-empuja con el reloj ACTUAL (recalcula "próximo" sin
      // datos rancios) y, si el plan cacheado es de otro día, lo refetch (el
      // listener de `planDiaProvider` empuja al widget cuando llegue el nuevo).
      _refrescarWidgetEnResume();
      // Notis proactivas: el plan pudo cambiar mientras estábamos fuera (otros
      // dispositivos, tools de Matix, paso del tiempo). Re-armamos las del
      // resto del día — best-effort, no bloquea el resume.
      unawaited(_refrescarNotisProactivasEnResume());
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

  /// Wake disparado con la app VIVA en background (otra app adelante). Decide:
  /// overlay flotante (si está habilitado + permitido) o fullscreen clásico.
  Future<void> _alWakeEnBackground() async {
    if (_overlayActivo || ref.read(modoVozActivoProvider)) return;
    final bg = ref.read(wakeWordBgServiceProvider);
    final prefs = WakeWordPrefs();
    final habilitado = await prefs.overlayVoz();
    final permitido = habilitado ? await bg.puedeOverlay() : false;
    final superficie = superficieParaWake(
      overlayHabilitado: habilitado,
      overlayPermitido: permitido,
      appEnPrimerPlano: false, // vino del path background
    );
    if (superficie == SuperficieWake.fullscreen) {
      _abrirManosLibresPorWakeWord(); // comportamiento clásico
      return;
    }
    await _iniciarOverlay();
  }

  /// Muestra la burbuja, manda Matix al fondo y corre el turno de voz HEADLESS
  /// (reusa la pipeline de manos libres, sin pantalla completa). Releva la fase
  /// a la burbuja y la cierra al terminar.
  Future<void> _iniciarOverlay() async {
    final bg = ref.read(wakeWordBgServiceProvider);
    final ok = await bg.overlayMostrar('escuchando');
    if (!ok) {
      // Sin permiso de overlay (degradación honesta): abrir fullscreen.
      _abrirManosLibresPorWakeWord();
      return;
    }
    _overlayActivo = true;
    await bg.enviarAlFondo(); // Matix atrás; el juego vuelve con la burbuja
    // Relé de fase y cierre automático al terminar (inactivo/error).
    _overlaySub = ref.listenManual<EstadoManosLibres>(
      manosLibresProvider,
      (prev, next) {
        if (!_overlayActivo) return;
        unawaited(bg.overlayActualizar(next.fase.name));
        if (next.fase == FaseManosLibres.inactivo ||
            next.fase == FaseManosLibres.error) {
          _cerrarOverlay();
        }
      },
    );
    await ref.read(manosLibresProvider.notifier).entrarPorWakeWord();
  }

  /// "Cerrar" (toque en la burbuja o fin de turno): termina la sesión y baja la
  /// burbuja. No persistente.
  void _cerrarOverlay() {
    if (!_overlayActivo) return;
    _overlayActivo = false; // guarda la re-entrada del listener (salir→inactivo)
    // salir() ANTES de cerrar la suscripción: así actúa sobre el notifier vivo
    // (la sub lo mantiene). Tras cerrar, autoDispose lo limpia.
    unawaited(ref.read(manosLibresProvider.notifier).salir());
    _overlaySub?.close();
    _overlaySub = null;
    unawaited(ref.read(wakeWordBgServiceProvider).overlayOcultar());
  }

  /// "Abrir" (toque en la burbuja): expande a Matix completo. La sesión sigue
  /// viva en el notifier; traemos la app al frente y mostramos la pantalla.
  void _expandirOverlay() {
    if (!_overlayActivo) return;
    _overlayActivo = false;
    _overlaySub?.close();
    _overlaySub = null;
    final bg = ref.read(wakeWordBgServiceProvider);
    unawaited(bg.overlayOcultar());
    unawaited(bg.traerAlFrente());
    final nav = _navigatorKey.currentState;
    if (nav != null && !_manosLibresEnStack) {
      _manosLibresEnStack = true;
      nav
          .push(MaterialPageRoute(
            builder: (_) => const ManosLibresScreen(porWakeWord: true),
          ))
          .then((_) => _manosLibresEnStack = false);
    }
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

  /// Al volver al frente: empuja el widget con el reloj ACTUAL (recalcula el
  /// "próximo", que es time-dependent y se vuelve rancio entre refrescos) y, si
  /// el plan cacheado es de OTRO día, lo invalida para refetch (cubre "día
  /// nuevo"); el listener de `planDiaProvider` empuja la versión fresca al llegar.
  void _refrescarWidgetEnResume() {
    final plan = ref.read(planDiaProvider).valueOrNull;
    final ahora = DateTime.now();
    final hoyIso = '${ahora.year.toString().padLeft(4, '0')}-'
        '${ahora.month.toString().padLeft(2, '0')}-'
        '${ahora.day.toString().padLeft(2, '0')}';
    if (plan == null || plan.fecha != hoyIso) {
      ref.invalidate(planDiaProvider);
    }
    if (plan != null) {
      unawaited(WidgetService.actualizar(plan, ahora));
    }
  }

  /// Refresca las notis proactivas locales al volver al frente. Throttled por
  /// `_ultimoRefrescoNotisProactivas`: como mínimo 10 min entre refrescos para
  /// no machacar el endpoint cada vez que el usuario abre la app por 2 s. El
  /// plan suele cambiar al hacer cosas dentro de la app (despertar/agendar);
  /// el on-resume cubre el caso "vine de fuera y mientras tanto Matix re-armó
  /// el día".
  Future<void> _refrescarNotisProactivasEnResume() async {
    final ahora = DateTime.now();
    final ultimo = _ultimoRefrescoNotisProactivas;
    if (ultimo != null && ahora.difference(ultimo).inMinutes < 10) return;
    _ultimoRefrescoNotisProactivas = ahora;
    try {
      await ref.read(notisProactivasServiceProvider).refrescar();
    } catch (_) {
      // best-effort; silenciamos
    }
  }

  /// Tap en un ítem/encabezado del widget de pantalla de inicio. El payload
  /// viaja en la query del URI (`matixwidget://abrir?payload=...`). Reusa el
  /// mismo enrutado que las notificaciones (Inicio / tarea / evento).
  void _enrutarPayloadWidget(Uri? uri) {
    if (uri == null) return;
    final payload = uri.queryParameters['payload'];
    _enrutarPayload(payload == null || payload.isEmpty ? 'hoy' : payload);
  }

  /// Marca una tarea como hecha desde el botón "hecho" del widget de Inicio
  /// (payload `completar:<id>`). Reusa la cadena probada de rendición de cuentas
  /// (`POST /push/rendicion-cuentas/accion`, accion='hecho'), refresca el hub y
  /// aterriza en Inicio para que el día y el widget reflejen el cambio.
  Future<void> _completarDesdeWidget(String tareaId) async {
    await manejarTapRendicionCuentas(tareaId: tareaId, accion: 'hecho');
    if (!mounted) return;
    invalidarHub(ref);
    ref.read(objetivoNavegacionProvider.notifier).state = SeccionMatix.inicio;
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
    } else if (payload == 'hoy' || payload == 'set_dia' || payload == 'rollover') {
      // Proactividad (pre-libre / hueco), el set del día y el rollover abren
      // Inicio, donde el robot ofrece lo tocable (mover/soltar) sin abrir chat.
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
    } else if (payload != null && payload.startsWith('completar:')) {
      // Botón "hecho" del widget de Inicio: completa la tarea sin abrir su
      // pantalla, reusando la cadena probada de rendición de cuentas.
      final idc = tareaIdDeCompletar(payload);
      if (idc != null) unawaited(_completarDesdeWidget(idc));
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
