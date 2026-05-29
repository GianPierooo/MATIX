import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../theme/matix_colors.dart';
import '../../../theme/matix_spacing.dart';
import '../../../theme/matix_typography.dart';
import '../application/captura_controller.dart';
import 'resultado_ocr_screen.dart';

/// Pantalla de cámara con preview en vivo + botón de captura (Capa 7-A).
///
/// Al disparar, toma la foto y se la pasa al [CapturaController], que
/// corre el OCR on-device. Cuando el controller termina (listo o
/// error) navegamos a [ResultadoOcrScreen] con el texto editable.
///
/// El `CameraController` reserva la cámara física: lo soltamos al salir
/// y cuando la app pasa a segundo plano (y lo re-armamos al volver),
/// para no quedarnos colgados del recurso.
class CapturaCamaraScreen extends ConsumerStatefulWidget {
  const CapturaCamaraScreen({super.key});

  @override
  ConsumerState<CapturaCamaraScreen> createState() =>
      _CapturaCamaraScreenState();
}

class _CapturaCamaraScreenState extends ConsumerState<CapturaCamaraScreen>
    with WidgetsBindingObserver {
  CameraController? _camara;
  bool _inicializando = true;
  bool _permisoDenegado = false;
  bool _permisoPermanente = false;
  String? _errorCamara;
  bool _capturando = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Si volvemos desde el resultado, reseteamos la fase a "cámara".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(capturaControllerProvider.notifier).reiniciar();
    });
    _arrancarCamara();
  }

  Future<void> _arrancarCamara() async {
    final estado = await Permission.camera.request();
    if (!estado.isGranted) {
      if (!mounted) return;
      setState(() {
        _permisoDenegado = true;
        _permisoPermanente = estado.isPermanentlyDenied;
        _inicializando = false;
      });
      return;
    }
    try {
      final camaras = await availableCameras();
      if (camaras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _errorCamara = 'Este teléfono no reporta ninguna cámara.';
          _inicializando = false;
        });
        return;
      }
      final trasera = camaras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => camaras.first,
      );
      final controller = CameraController(
        trasera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camara = controller;
        _inicializando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorCamara = '$e';
        _inicializando = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _camara;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _camara = null;
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _inicializando = true;
      _arrancarCamara();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camara?.dispose();
    super.dispose();
  }

  Future<void> _capturar() async {
    final c = _camara;
    if (c == null || !c.value.isInitialized || _capturando) return;
    setState(() => _capturando = true);
    try {
      final foto = await c.takePicture();
      await ref
          .read(capturaControllerProvider.notifier)
          .procesarFoto(foto.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pude tomar la foto: $e')),
      );
    } finally {
      if (mounted) setState(() => _capturando = false);
    }
  }

  void _escribirAMano(String aviso) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResultadoOcrScreen(textoInicial: '', aviso: aviso),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Cuando el OCR termina, saltamos al resultado editable.
    ref.listen<EstadoCaptura>(capturaControllerProvider, (prev, next) {
      if (next.fase == FaseCaptura.listo) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ResultadoOcrScreen(
              textoInicial: next.texto,
              aviso: next.vacio
                  ? 'No detecté texto en la foto. Escríbelo a mano.'
                  : null,
            ),
          ),
        );
      } else if (next.fase == FaseCaptura.error) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ResultadoOcrScreen(
              textoInicial: '',
              aviso: next.error ?? 'No pude leer el texto. Escríbelo a mano.',
            ),
          ),
        );
      }
    });

    final procesando =
        ref.watch(capturaControllerProvider).fase == FaseCaptura.procesando;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Capturar texto'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _construirCuerpo(procesando),
    );
  }

  Widget _construirCuerpo(bool procesando) {
    if (_inicializando) {
      return const Center(
        child: CircularProgressIndicator(color: MatixColors.accent),
      );
    }
    if (_permisoDenegado) {
      return _SinCamara(
        icono: Icons.no_photography_outlined,
        titulo: 'Sin acceso a la cámara',
        mensaje: _permisoPermanente
            ? 'Bloqueaste el permiso de cámara. Ábrelo desde los ajustes '
                'del sistema, o escribe el texto a mano.'
            : 'Necesito permiso de cámara para capturar. Puedes concederlo '
                'o escribir el texto a mano.',
        accionExtra: _permisoPermanente
            ? _BotonAccion(
                texto: 'Abrir ajustes',
                onPressed: openAppSettings,
              )
            : _BotonAccion(
                texto: 'Conceder permiso',
                onPressed: () {
                  setState(() {
                    _inicializando = true;
                    _permisoDenegado = false;
                  });
                  _arrancarCamara();
                },
              ),
        onEscribir: () =>
            _escribirAMano('Sin cámara. Escribe el texto a mano.'),
      );
    }
    if (_errorCamara != null) {
      return _SinCamara(
        icono: Icons.error_outline,
        titulo: 'No pude abrir la cámara',
        mensaje: _errorCamara!,
        onEscribir: () => _escribirAMano(
          'No se pudo usar la cámara. Escribe el texto a mano.',
        ),
      );
    }

    final camara = _camara;
    if (camara == null || !camara.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: CameraPreview(camara)),
        if (procesando)
          Container(
            color: Colors.black.withValues(alpha: 0.6),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: MatixColors.accent),
                  SizedBox(height: MatixSpacing.l),
                  Text(
                    'Extrayendo texto…',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        if (!procesando)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 36),
              child: _BotonDisparo(
                ocupado: _capturando,
                onTap: _capturar,
              ),
            ),
          ),
      ],
    );
  }
}

class _BotonDisparo extends StatelessWidget {
  const _BotonDisparo({required this.ocupado, required this.onTap});
  final bool ocupado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: ocupado ? null : onTap,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.18),
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: ocupado
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: MatixColors.accent,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _SinCamara extends StatelessWidget {
  const _SinCamara({
    required this.icono,
    required this.titulo,
    required this.mensaje,
    required this.onEscribir,
    this.accionExtra,
  });

  final IconData icono;
  final String titulo;
  final String mensaje;
  final VoidCallback onEscribir;
  final Widget? accionExtra;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MatixSpacing.xl4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, color: MatixColors.muted, size: 56),
            const SizedBox(height: MatixSpacing.xl),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: MatixText.subtitle.copyWith(color: Colors.white),
            ),
            const SizedBox(height: MatixSpacing.m),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: MatixText.small,
            ),
            const SizedBox(height: MatixSpacing.xl2),
            if (accionExtra != null) ...[
              accionExtra!,
              const SizedBox(height: MatixSpacing.m),
            ],
            TextButton(
              onPressed: onEscribir,
              child: const Text('Escribir a mano'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BotonAccion extends StatelessWidget {
  const _BotonAccion({required this.texto, required this.onPressed});
  final String texto;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: MatixColors.accent,
        foregroundColor: Colors.white,
      ),
      child: Text(texto),
    );
  }
}
