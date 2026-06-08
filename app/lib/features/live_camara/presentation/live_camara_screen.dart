import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/providers.dart';
import '../../../theme/matix_colors.dart';
import '../../matix/data/tts_service.dart';
import '../data/narracion_repository.dart';
import '../domain/muestreo.dart';

/// Cámara EN VIVO: Matix narra en voz lo que ve, de forma continua, con
/// muestreo inteligente y topes de costo. Hands-free; control por toque (STOP
/// grande). La pantalla es dueña de la cámara, el loop y el TTS; la lógica de
/// muestreo/topes (pura) vive en domain/muestreo.dart.
class LiveCamaraScreen extends ConsumerStatefulWidget {
  const LiveCamaraScreen({super.key});

  @override
  ConsumerState<LiveCamaraScreen> createState() => _LiveCamaraScreenState();
}

enum _Fase { iniciando, observando, narrando, terminado, error }

class _LiveCamaraScreenState extends ConsumerState<LiveCamaraScreen>
    with WidgetsBindingObserver {
  static const _pol = PoliticaMuestreo();

  CameraController? _camara;
  late final TtsService _tts;
  late final NarracionRepository _repo;

  bool _activa = false;
  _Fase _fase = _Fase.iniciando;
  String? _error;
  // La voz falló al menos una vez en esta sesión (502/timeout tras reintentos).
  // La cámara sigue narrando en TEXTO; solo lo avisamos honesto.
  bool _sinVoz = false;
  bool _vozTelefono = false;
  // Sirve de chip diagnóstico ("dispositivo" / "cloud (respaldo)" / "sin voz").
  // Se actualiza tras cada turno con lo que reporta `TtsService.ultimoEvento`.
  String _vozFuente = '';

  // Estado del muestreo / costo.
  DateTime? _inicioSesion;
  DateTime? _ultimoEnvio;
  final List<DateTime> _envios = [];
  List<int>? _firmaPrevia;
  String? _narracionPrevia;
  int _estaticos = 0;
  int _framesEnviados = 0;
  int _caracteresTts = 0;
  String _narracionActual = '';
  RazonCorte? _razonCorte;

  // ── Concurrencia del loop (último frame gana, sin cola) ──────────────────
  // El frame MÁS fresco que pasó el muestreo y espera visión. El loop de
  // captura lo SOBREESCRIBE (no encola): cuando la visión se libera, narra el
  // más reciente y descarta los intermedios viejos.
  ({Uint8List bytes, List<int> firma, DateTime t})? _pendiente;
  // Hay una petición de visión EN VUELO (una sola a la vez).
  bool _enVuelo = false;
  // "mirando…": indicador honesto mientras la visión piensa (no congelado).
  bool _pensando = false;

  Duration get _transcurrido =>
      _inicioSesion == null ? Duration.zero : DateTime.now().difference(_inicioSesion!);
  double get _costo =>
      costoEstimadoUsd(framesEnviados: _framesEnviados, caracteresTts: _caracteresTts);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tts = TtsService();
    _repo = NarracionRepository(ref.read(matixClientProvider));
    // Inicializar el TTS del dispositivo eager: idioma con fallback Latam,
    // velocidad/volumen, modo FLUSH. Si no se hace acá, la primera frase paga
    // el setup (medio segundo en algunos OEM) y se siente atrasada.
    unawaited(_tts.prepararDispositivo());
    WidgetsBinding.instance.addPostFrameCallback((_) => _arrancar());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _activa = false;
    _tts.detener();
    _camara?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Si la app pasa a segundo plano, cortamos la sesión: NUNCA debe quedar
    // corriendo sola (guardrail de costo).
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_activa) _detener(razon: null, mensaje: 'Pausé la sesión.');
    }
  }

  Future<void> _arrancar() async {
    final permiso = await Permission.camera.request();
    if (!permiso.isGranted) {
      _fallar('Necesito permiso de cámara para esto.');
      return;
    }
    try {
      final camaras = await availableCameras();
      if (camaras.isEmpty) {
        _fallar('No encuentro ninguna cámara.');
        return;
      }
      final trasera = camaras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => camaras.first,
      );
      final c = CameraController(
        trasera,
        ResolutionPreset.medium, // medio: takePicture rápido y subida liviana
        enableAudio: false,
      );
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _camara = c;
        _activa = true;
        _fase = _Fase.observando;
        _inicioSesion = DateTime.now();
        // Arranque limpio del loop (también al REANUDAR): sin frame pendiente
        // viejo ni indicadores colgados de una sesión anterior.
        _pendiente = null;
        _enVuelo = false;
        _pensando = false;
      });
      // Saludo de apertura: device-first (rápido, sin red, simultáneo con el
      // texto). Si el motor del dispositivo no habla, cae al cloud como
      // respaldo. Antes era cloud-first y se sentía 1–2s atrasado o muteado.
      _tts.narrarRapido(
        'Listo, te voy contando lo que veo.',
        onFallo: _avisarSinVoz,
        onDispositivo: _avisarVozTelefono,
        onCloud: _avisarVozCloud,
      );
      // Dos loops DESACOPLADOS (no en serie): la captura nunca espera a la
      // visión, y la visión nunca espera al audio. Así el ritmo es humano y
      // no se acumula cola ni se narran escenas viejas.
      unawaited(_loopCaptura());
      unawaited(_loopVision());
    } catch (e) {
      _fallar('No pude abrir la cámara: $e');
    }
  }

  void _avisarSinVoz() {
    if (!mounted) return;
    setState(() {
      _sinVoz = true;
      _vozFuente = _tts.ultimoEvento?.etiqueta ?? '';
    });
  }

  void _avisarVozTelefono() {
    // Voz del dispositivo (camino feliz device-first): rápida y sin red.
    if (!mounted) return;
    setState(() {
      _vozTelefono = true;
      _sinVoz = false;
      final idioma = _tts.idiomaDispositivo;
      _vozFuente =
          idioma == null ? 'dispositivo' : 'dispositivo · $idioma';
    });
  }

  void _avisarVozCloud() {
    // Device falló: salió por el respaldo cloud (lento pero al menos suena).
    if (!mounted) return;
    setState(() {
      _vozTelefono = true; // mantenemos el aviso pero con etiqueta cloud
      _sinVoz = false;
      _vozFuente = 'cloud (respaldo)';
    });
  }

  /// Loop de CAPTURA: muestrea a ritmo humano y deja el frame más fresco que
  /// pasó el filtro en `_pendiente` (ÚLTIMO GANA: sobreescribe, no encola).
  /// Nunca espera a la visión ni al audio. Reusa el muestreo y los topes ya
  /// existentes (intervalo, cambio de escena, frames/min) y el auto-corte.
  Future<void> _loopCaptura() async {
    while (_activa && mounted) {
      final t = DateTime.now();
      try {
        await _capturar(t);
      } catch (_) {
        // Best-effort: un frame que falla no tumba la sesión.
      }
      if (!_activa || !mounted) break;
      final espera = _pol.intervalo - DateTime.now().difference(t);
      if (espera > Duration.zero) await Future<void>.delayed(espera);
    }
  }

  Future<void> _capturar(DateTime ahora) async {
    final c = _camara;
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture) return;

    // Corte por topes (duración / sin cambios) ANTES de gastar otro frame:
    // los guardrails de costo y el auto-stop se mantienen intactos.
    final corte = debeCortar(
      inicio: _inicioSesion!,
      ahora: ahora,
      estaticosSeguidos: _estaticos,
      politica: _pol,
    );
    if (corte.cortar) {
      await _detener(razon: corte.razon);
      return;
    }

    final XFile foto = await c.takePicture();
    final Uint8List bytes = await foto.readAsBytes();
    final firma = await _firma(bytes);

    final cambio = hayCambioSignificativo(_firmaPrevia, firma, _pol.umbralCambio);
    final decision = decidirEnvio(
      ahora: ahora,
      ultimoEnvio: _ultimoEnvio,
      hayCambio: cambio,
      framesUltimoMinuto: framesEnUltimoMinuto(_envios, ahora),
      politica: _pol,
    );

    if (!decision.enviar) {
      if (decision.motivo == MotivoNoEnvio.sinCambio) {
        _estaticos++;
        if (mounted) setState(() {});
      }
      return;
    }

    // Pasó el filtro: queda como el frame más fresco a narrar. Si ya había uno
    // pendiente sin procesar, lo PISA (último gana — descarta el viejo).
    _pendiente = (bytes: bytes, firma: firma, t: ahora);
  }

  /// Loop de VISIÓN: una sola petición en vuelo. Cuando se libera, toma el
  /// frame MÁS fresco disponible, narra, y vuelve a tomar el siguiente más
  /// fresco. Nunca espera al audio (el TTS va en segundo plano e interrumpible).
  Future<void> _loopVision() async {
    while (_activa && mounted) {
      final frame = _pendiente;
      if (frame == null || _enVuelo) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        continue;
      }
      _pendiente = null; // lo tomo; lo que llegue después será el próximo
      await _narrarFrame(frame);
    }
  }

  Future<void> _narrarFrame(
    ({Uint8List bytes, List<int> firma, DateTime t}) frame,
  ) async {
    _enVuelo = true;
    // Contabilidad de costo: cuenta como envío real recién ahora (no en captura).
    _ultimoEnvio = frame.t;
    _envios.add(frame.t);
    _firmaPrevia = frame.firma;
    _framesEnviados++;
    if (mounted) {
      setState(() {
        _fase = _Fase.narrando;
        _pensando = true; // "mirando…": honesto mientras el modelo piensa
      });
    }
    try {
      final dataUrl = 'data:image/jpeg;base64,${base64Encode(frame.bytes)}';
      final narracion =
          await _repo.narrarFrame(dataUrl, previa: _narracionPrevia);
      if (!_activa || !mounted) return;
      if (narracion.isEmpty) {
        _estaticos++; // el modelo dijo "sin cambios" (o se saltó el frame)
      } else {
        _estaticos = 0;
        _narracionPrevia = narracion;
        _caracteresTts += narracion.length;
        // El TEXTO se muestra YA; la voz va en segundo plano, interrumpible, y
        // nunca bloquea el loop. Si la voz falla, seguimos narrando en texto.
        setState(() => _narracionActual = narracion);
        // Device-first: la voz arranca a la par del texto, sin esperar la red.
        _tts.narrarRapido(
          narracion,
          onFallo: _avisarSinVoz,
          onDispositivo: _avisarVozTelefono,
          onCloud: _avisarVozCloud,
        );
      }
    } catch (_) {
      // Un frame que falla (timeout/red) no tumba la sesión: se salta.
    } finally {
      _enVuelo = false;
      if (mounted && _activa) {
        setState(() {
          _fase = _Fase.observando;
          _pensando = false;
        });
      }
    }
  }

  /// Firma del frame: thumbnail 16x16 en gris (256 valores), vía dart:ui.
  Future<List<int>> _firma(Uint8List jpeg) async {
    final codec = await ui.instantiateImageCodec(
      jpeg,
      targetWidth: 16,
      targetHeight: 16,
    );
    final frame = await codec.getNextFrame();
    final bd = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    final px = bd!.buffer.asUint8List();
    final out = <int>[];
    for (var i = 0; i + 2 < px.length; i += 4) {
      out.add((px[i] + px[i + 1] + px[i + 2]) ~/ 3);
    }
    return out;
  }

  Future<void> _detener({RazonCorte? razon, String? mensaje}) async {
    if (!_activa) return;
    _activa = false;
    if (mounted) {
      setState(() {
        _fase = _Fase.terminado;
        _razonCorte = razon;
      });
    }
    final txt = mensaje ??
        switch (razon) {
          RazonCorte.topeSesion =>
            'Corté la sesión por el tope de tiempo. La retomas cuando quieras.',
          RazonCorte.sinCambios =>
            'No veía cambios, así que cerré para no gastar de más.',
          null => 'Listo, cerré la sesión.',
        };
    // Despedida también device-first: corta y rápida, al cerrar la sesión.
    _tts.narrarRapido(txt);
  }

  void _fallar(String msg) {
    if (!mounted) return;
    setState(() {
      _fase = _Fase.error;
      _error = msg;
      _activa = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _camara;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (c != null && c.value.isInitialized)
            CameraPreview(c)
          else
            const ColoredBox(color: Colors.black),
          // Velo para que el texto blanco se lea sobre cualquier escena.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.transparent, Colors.black87],
                stops: [0, 0.35, 1],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _BarraSuperior(
                  enVivo: _activa,
                  transcurrido: _transcurrido,
                  topeSesion: _pol.topeSesion,
                  costo: _costo,
                  frames: _framesEnviados,
                ),
                const Spacer(),
                if (_fase == _Fase.error)
                  _Aviso(_error ?? 'Algo falló.', icono: Icons.error_outline)
                else if (_fase == _Fase.terminado)
                  _Aviso(
                    _razonCorte == RazonCorte.topeSesion
                        ? 'Sesión cerrada por el tope de tiempo.'
                        : _razonCorte == RazonCorte.sinCambios
                            ? 'Cerré la sesión: no había cambios.'
                            : 'Sesión cerrada.',
                    icono: Icons.stop_circle_outlined,
                  )
                else if (_narracionActual.isNotEmpty)
                  _Narracion(_narracionActual),
                // Indicador honesto de que sigue vivo mientras la visión piensa
                // (no congelado). Solo en vivo y cuando hay una petición en vuelo.
                if (_activa &&
                    _pensando &&
                    _fase != _Fase.terminado &&
                    _fase != _Fase.error) ...[
                  const SizedBox(height: 10),
                  const _Mirando(),
                ],
                if (_activa && _sinVoz) ...[
                  const SizedBox(height: 8),
                  _AvisoSinVoz(motivo: _vozFuente),
                ] else if (_activa && _vozTelefono) ...[
                  const SizedBox(height: 8),
                  _AvisoVozTelefono(fuente: _vozFuente),
                ],
                const SizedBox(height: 16),
                _Controles(
                  activa: _activa,
                  terminado: _fase == _Fase.terminado || _fase == _Fase.error,
                  onParar: () => _detener(mensaje: 'Listo, paré la sesión.'),
                  onSalir: () => Navigator.of(context).maybePop(),
                  onReanudar: _arrancar,
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarraSuperior extends StatelessWidget {
  const _BarraSuperior({
    required this.enVivo,
    required this.transcurrido,
    required this.topeSesion,
    required this.costo,
    required this.frames,
  });
  final bool enVivo;
  final Duration transcurrido;
  final Duration topeSesion;
  final double costo;
  final int frames;

  String _mmss(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle,
                    size: 10,
                    color: enVivo ? MatixColors.red : MatixColors.muted),
                const SizedBox(width: 6),
                Text(
                  enVivo ? 'EN VIVO' : 'PAUSA',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_mmss(transcurrido)} / ${_mmss(topeSesion)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '≈ \$${costo.toStringAsFixed(3)} · $frames',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Narracion extends StatelessWidget {
  const _Narracion(this.texto);
  final String texto;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        texto,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w600,
          height: 1.3,
          shadows: [Shadow(color: Colors.black, blurRadius: 8)],
        ),
      ),
    );
  }
}

/// Indicador honesto "mirando…": un puntito que late mientras la visión piensa,
/// para que la sesión no se sienta congelada entre narraciones.
class _Mirando extends StatefulWidget {
  const _Mirando();
  @override
  State<_Mirando> createState() => _MirandoState();
}

class _MirandoState extends State<_Mirando>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_ctrl),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.visibility_outlined, color: Colors.white70, size: 16),
          SizedBox(width: 6),
          Text(
            'mirando…',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip diagnóstico del proveedor de voz. Muestra de qué fuente salió (device
/// o cloud-respaldo), con icono y locale si está disponible.
class _AvisoVozTelefono extends StatelessWidget {
  const _AvisoVozTelefono({this.fuente = ''});
  final String fuente;
  @override
  Widget build(BuildContext context) {
    final esCloud = fuente.toLowerCase().contains('cloud');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            esCloud ? Icons.cloud_outlined : Icons.phone_android_rounded,
            color: Colors.white70,
            size: 16,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              fuente.isEmpty
                  ? 'Usando la voz del teléfono.'
                  : 'Voz: $fuente',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso discreto cuando la voz no salió: la cámara sigue narrando en texto.
/// Honesto, sin alarmar — NO es "no pude abrir la cámara".
class _AvisoSinVoz extends StatelessWidget {
  const _AvisoSinVoz({this.motivo = ''});
  final String motivo;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.volume_off_rounded, color: Colors.white70, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              motivo.isEmpty
                  ? 'Voz no disponible ahora; sigo contándote en texto.'
                  : 'Voz no disponible ($motivo); sigo en texto.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso(this.texto, {required this.icono});
  final String texto;
  final IconData icono;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, color: Colors.white, size: 30),
          const SizedBox(height: 8),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.3),
          ),
        ],
      ),
    );
  }
}

class _Controles extends StatelessWidget {
  const _Controles({
    required this.activa,
    required this.terminado,
    required this.onParar,
    required this.onSalir,
    required this.onReanudar,
  });
  final bool activa;
  final bool terminado;
  final VoidCallback onParar;
  final VoidCallback onSalir;
  final VoidCallback onReanudar;

  @override
  Widget build(BuildContext context) {
    if (activa) {
      // Botón STOP grande y claro: siempre a la mano.
      return _BotonGrande(
        label: 'Parar',
        icono: Icons.stop_rounded,
        color: MatixColors.red,
        onTap: onParar,
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (terminado)
          _BotonGrande(
            label: 'De nuevo',
            icono: Icons.play_arrow_rounded,
            color: MatixColors.accent,
            onTap: onReanudar,
          ),
        const SizedBox(width: 12),
        _BotonGrande(
          label: 'Salir',
          icono: Icons.close_rounded,
          color: MatixColors.card,
          onTap: onSalir,
        ),
      ],
    );
  }
}

class _BotonGrande extends StatelessWidget {
  const _BotonGrande({
    required this.label,
    required this.icono,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icono;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
