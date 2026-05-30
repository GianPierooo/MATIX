import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../theme/matix_colors.dart';
import '../application/captura_controller.dart';
import 'resultado_ocr_screen.dart';

/// Flujo "sílabo → eventos" (Cámara · sílabo):
///
/// 1. Sheet de origen: cámara o galería.
/// 2. `ImagePicker` levanta la foto del sílabo/horario.
/// 3. ML Kit extrae el texto **en el teléfono** (mismo `OcrService` que
///    tareas — la imagen NO sale del dispositivo).
/// 4. Pantalla editable (`ResultadoOcrScreen`, destino eventos) para
///    corregir el OCR.
/// 5. Al confirmar, el TEXTO va al cerebro, que propone eventos
///    (clases recurrentes + fechas únicas) para revisar y crear.
Future<void> iniciarFlujoSilaboDesdeFoto(
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
  if (picked == null) return;

  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ProgresoSilabo(imagen: File(picked!.path)),
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
                'Escanear sílabo u horario',
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
            leading: const Icon(Icons.camera_alt_outlined,
                color: MatixColors.accent),
            title: const Text('Tomar foto'),
            subtitle: const Text('Abrir la cámara'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined,
                color: MatixColors.accent),
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

class _ProgresoSilabo extends ConsumerStatefulWidget {
  const _ProgresoSilabo({required this.imagen});
  final File imagen;

  @override
  ConsumerState<_ProgresoSilabo> createState() => _ProgresoSilaboState();
}

class _ProgresoSilaboState extends ConsumerState<_ProgresoSilabo> {
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
      final texto =
          await ref.read(ocrServiceProvider).extraerTexto(widget.imagen.path);
      try {
        await widget.imagen.delete();
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResultadoOcrScreen(
            destino: DestinoOcr.eventos,
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
        title: const Text('Escanear sílabo'),
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
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(widget.imagen, height: 200, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                if (!_error)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: MatixColors.accent),
                  )
                else
                  const Icon(Icons.error_outline,
                      color: MatixColors.red, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _error
                        ? (_mensaje ?? 'Algo falló.')
                        : 'Leyendo el texto en el teléfono…',
                    style: const TextStyle(
                        fontSize: 14, color: MatixColors.text),
                  ),
                ),
              ],
            ),
            if (_error) ...[
              const SizedBox(height: 16),
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
