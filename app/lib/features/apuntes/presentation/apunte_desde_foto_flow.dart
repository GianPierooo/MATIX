import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../theme/matix_colors.dart';
import '../../captura_camara/application/captura_controller.dart';
import '../../captura_camara/presentation/resultado_ocr_screen.dart';

/// Orquesta el flujo "apunte desde foto" (Capa 7 · unificado a OCR
/// on-device):
///
/// 1. Sheet de origen: cámara o galería.
/// 2. `ImagePicker` levanta la foto.
/// 3. Pantalla intermedia: ML Kit extrae el texto **en el teléfono**
///    (mismo `OcrService` que el flujo de tareas — la imagen NO sale
///    del dispositivo).
/// 4. Pantalla editable (`ResultadoOcrScreen`, destino apunte) para
///    corregir lo que el OCR haya errado.
/// 5. Al confirmar, el TEXTO va a `/matix/capturar-apunte`, que lo
///    clasifica en proyecto / curso / general como cualquier otro
///    apunte (reusa el flujo del Paso C).
///
/// Punto de entrada único: `iniciarFlujoApunteDesdeFoto(context, ref)`.
Future<void> iniciarFlujoApunteDesdeFoto(
  BuildContext context,
  WidgetRef ref,
) async {
  final origen = await _mostrarSheetOrigen(context);
  if (origen == null) return;

  final picker = ImagePicker();
  final XFile? picked;
  try {
    picked = await picker.pickImage(
      source: origen,
      // Comprimimos un poco: ML Kit no necesita la foto a resolución
      // completa para leer texto, y así el archivo temporal pesa menos.
      imageQuality: 85,
      maxWidth: 2400,
      maxHeight: 2400,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pude abrir la cámara / galería: $e')),
      );
    }
    return;
  }
  if (picked == null) return; // usuario canceló

  if (!context.mounted) return;
  // Pantalla que corre el OCR on-device y navega al texto editable.
  await Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ProgresoApunteDesdeFoto(imagen: File(picked!.path)),
    ),
  );
}

Future<ImageSource?> _mostrarSheetOrigen(BuildContext context) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: MatixColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: MatixColors.muted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Apunte desde foto',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: MatixColors.text,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(
              Icons.camera_alt_outlined,
              color: MatixColors.accent,
            ),
            title: const Text('Tomar foto'),
            subtitle: const Text('Abrir la cámara'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(
              Icons.photo_library_outlined,
              color: MatixColors.accent,
            ),
            title: const Text('Elegir de la galería'),
            subtitle: const Text('Usar una foto existente'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _ProgresoApunteDesdeFoto extends ConsumerStatefulWidget {
  const _ProgresoApunteDesdeFoto({required this.imagen});
  final File imagen;

  @override
  ConsumerState<_ProgresoApunteDesdeFoto> createState() =>
      _ProgresoApunteDesdeFotoState();
}

class _ProgresoApunteDesdeFotoState
    extends ConsumerState<_ProgresoApunteDesdeFoto> {
  bool _error = false;
  String? _mensaje;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _extraer());
  }

  Future<void> _extraer() async {
    setState(() {
      _error = false;
      _mensaje = null;
    });
    try {
      // OCR on-device con ML Kit: la imagen nunca sale del teléfono.
      final texto =
          await ref.read(ocrServiceProvider).extraerTexto(widget.imagen.path);
      // La foto ya cumplió su rol; la borramos del temporal. Si el
      // borrado falla no es crítico (el SO limpia la cache).
      try {
        await widget.imagen.delete();
      } catch (_) {}

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResultadoOcrScreen(
            destino: DestinoOcr.apunte,
            textoInicial: texto,
            aviso: texto.isEmpty
                ? 'No detecté texto en la foto. Escríbelo a mano.'
                : null,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _mensaje = 'No pude leer el texto de la foto: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Apunte desde foto'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview de la foto que se está leyendo, como referencia.
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  widget.imagen,
                  height: 200,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _Paso(
              activo: !_error,
              texto: 'Leyendo el texto en el teléfono…',
            ),
            const SizedBox(height: 24),
            if (_error) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MatixColors.red.withValues(alpha: 0.12),
                  border: Border.all(
                    color: MatixColors.red.withValues(alpha: 0.45),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _mensaje ?? 'Algo falló.',
                  style: const TextStyle(
                    color: MatixColors.text,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _extraer,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
                style: FilledButton.styleFrom(
                  backgroundColor: MatixColors.accent,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Paso extends StatelessWidget {
  const _Paso({required this.activo, required this.texto});
  final bool activo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (activo)
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: MatixColors.accent,
            ),
          )
        else
          const Icon(
            Icons.radio_button_unchecked,
            color: MatixColors.muted,
            size: 22,
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 14,
              color: activo ? MatixColors.text : MatixColors.muted,
              fontWeight: activo ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
