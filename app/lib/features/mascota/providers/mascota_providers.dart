import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../matix/providers/matix_chat_providers.dart';
import '../../matix/providers/navegacion_matix_provider.dart';
import '../../proyectos/providers/proyectos_providers.dart';
import '../../tareas/providers/tareas_providers.dart';
import '../data/mascota_prefs.dart';
import '../domain/dosificacion.dart';
import '../domain/personalidad.dart';

/// Contexto vivo de la mascota, derivado de lo que ya está cargado (tareas y
/// proyectos). Liviano y sin red: alimenta el copy contextual.
final contextoMascotaProvider = Provider<ContextoMascota>((ref) {
  final tareas = ref.watch(tareasProvider).valueOrNull ?? const [];
  final proyectos = ref.watch(proyectosListProvider).valueOrNull ?? const [];
  final ahora = DateTime.now();

  bool esHoy(DateTime? d) {
    if (d == null) return false;
    final l = d.toLocal();
    return l.year == ahora.year && l.month == ahora.month && l.day == ahora.day;
  }

  final pendientes = tareas.where((t) => !t.completada).toList();
  final tareasHoy = pendientes.where((t) {
    final d = t.plazoEfectivo;
    return d != null && (esHoy(d) || d.isBefore(ahora));
  }).length;
  final vencidas = pendientes.where((t) => t.estaVencida).length;
  final hechasHoy =
      tareas.where((t) => t.completada && esHoy(t.completadaEn)).length;
  final activos = proyectos.where((p) => p.esActivo && !p.esSkill).toList();
  final enRiesgo = activos.where((p) => p.enRiesgo).length;

  return ContextoMascota(
    tareasHoy: tareasHoy,
    vencidas: vencidas,
    hechasHoy: hechasHoy,
    proyectosActivos: activos.length,
    proyectosEnRiesgo: enRiesgo,
  );
});

/// Config de la mascota para Ajustes (on/off + frecuencia). Persiste local.
class MascotaConfigController extends Notifier<MascotaConfig> {
  final _prefs = MascotaPrefs();

  @override
  MascotaConfig build() {
    _cargar();
    return const MascotaConfig();
  }

  Future<void> _cargar() async {
    state = await _prefs.leerConfig();
  }

  Future<void> setHabilitada(bool v) async {
    state = state.copyWith(habilitada: v);
    await _prefs.guardarConfig(state);
  }

  Future<void> setFrecuencia(FrecuenciaMascota f) async {
    state = state.copyWith(frecuencia: f);
    await _prefs.guardarConfig(state);
  }
}

final mascotaConfigProvider =
    NotifierProvider<MascotaConfigController, MascotaConfig>(
        MascotaConfigController.new);

/// Controla la BURBUJA flotante de la mascota (apariciones + despedida). El
/// saludo persistente vive en la tarjeta de Inicio, no acá. `null` = sin
/// burbuja. Dosificado y anti-fastidio: respeta silencio, frecuencia y baja si
/// lo ignoras.
class MascotaController extends Notifier<MensajeMascota?> {
  final _prefs = MascotaPrefs();

  @override
  MensajeMascota? build() => null;

  /// Quizás aparece (al volver al frente). No pisa una burbuja ya visible.
  Future<void> quizasAparecer() async {
    if (state != null) return;
    final cfg = await _prefs.leerConfig();
    final ahora = DateTime.now();
    final ultima = await _prefs.ultimaAparicion();
    final ignoradas = await _prefs.ignoradasSeguidas();
    final puede = puedeAparecer(
      habilitado: cfg.habilitada,
      ahora: ahora,
      ultima: ultima,
      ignoradasSeguidas: ignoradas,
      silencioInicio: cfg.silencioInicio,
      silencioFin: cfg.silencioFin,
      frecuencia: cfg.frecuencia,
    );
    if (!puede) return;
    final ctx = ref.read(contextoMascotaProvider);
    final semilla = ahora.day + ahora.hour;
    final tipo = elegirAparicion(ctx, semilla: semilla);
    state = aparicion(tipo, ctx, semilla: semilla);
    await _prefs.marcarAparicion(ahora);
  }

  /// Prepara la despedida al salir (la pinta la burbuja). Devuelve `true` si la
  /// mostró, para que quien cierra la app espere un instante a que se vea.
  Future<bool> prepararDespedida() async {
    final cfg = await _prefs.leerConfig();
    final ahora = DateTime.now();
    final ultima = await _prefs.ultimaDespedida();
    final puede = puedeDespedir(
      habilitado: cfg.habilitada,
      ahora: ahora,
      ultimaDespedida: ultima,
      silencioInicio: cfg.silencioInicio,
      silencioFin: cfg.silencioFin,
    );
    if (!puede) return false;
    state = despedida(franjaDe(ahora.hour), semilla: ahora.day + ahora.minute);
    await _prefs.marcarDespedida(ahora);
    return true;
  }

  /// Toca una opción de la burbuja. Reusa el chat y la navegación existentes.
  Future<void> responder(String opcion) async {
    final msg = state;
    state = null;
    await _prefs.registrarRespuesta(interactuo: true);
    if (opcion == 'Ver mi día') {
      ref.read(objetivoNavegacionProvider.notifier).state = SeccionMatix.inicio;
      return;
    }
    if (opcion == 'Hablemos') {
      ref.read(objetivoNavegacionProvider.notifier).state = SeccionMatix.matix;
      // Semilla natural para que Matix responda con contexto (1 turno, iniciado
      // por el usuario al tocar — barato y esperado).
      final seed = _seedDeTipo(msg?.tipo);
      if (seed != null) {
        await ref.read(chatMatixProvider.notifier).enviar(seed);
      }
    }
    // 'Gracias' / 'Seguimos' / 'Ahora no' positivos: solo cierran (ya registramos
    // interacción), sin abrir nada.
  }

  /// Cierra la burbuja sin interactuar (la ignoró): sube la racha para bajar el
  /// volumen la próxima.
  Future<void> descartar() async {
    state = null;
    await _prefs.registrarRespuesta(interactuo: false);
  }

  String? _seedDeTipo(TipoMascota? tipo) => switch (tipo) {
        TipoMascota.empujoncito => '¿Qué me conviene retomar ahora?',
        TipoMascota.aliento => 'Cuéntame algo para arrancar.',
        TipoMascota.comentario => 'Hola, ¿cómo vamos?',
        TipoMascota.felicitacion => '¿Qué sigue?',
        TipoMascota.despedida => null,
        TipoMascota.saludo => 'Hola, ¿cómo vamos?',
        null => 'Hola',
      };
}

final mascotaControllerProvider =
    NotifierProvider<MascotaController, MensajeMascota?>(MascotaController.new);
