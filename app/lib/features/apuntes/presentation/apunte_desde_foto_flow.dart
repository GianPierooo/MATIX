import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../api/matix_client.dart';
import '../../../theme/matix_colors.dart';
import '../data/apuntes_foto_repository.dart';
import '../providers/apuntes_providers.dart';
import 'editor_apunte_screen.dart';

/// Orquesta el flujo completo "apunte desde foto" (Capa 7 · Paso 1):
///
/// 1. Sheet de origen: cámara o galería.
/// 2. `ImagePicker` levanta la foto.
/// 3. Pantalla intermedia con stepper (Subiendo → Extrayendo).
/// 4. POST al cerebro vía `ApuntesFotoRepository`.
/// 5. Navegamos al editor del apunte recién creado. Si OCR falló,
///    el editor pinta un banner ámbar (lo lee del state inicial).
///
/// Punto de entrada único: `iniciar(context, ref, ...)`. Cualquier
/// pantalla que quiera disparar el flujo lo invoca con sus
/// metadatos opcionales (curso_id típicamente).
Future<void> iniciarFlujoApunteDesdeFoto(
  BuildContext context,
  WidgetRef ref, {
  String? cursoId,
  String? proyectoId,
  String? cuadernoId,
}) async {
  final origen = await _mostrarSheetOrigen(context);
  if (origen == null) return;

  final picker = ImagePicker();
  final XFile? picked;
  try {
    picked = await picker.pickImage(
      source: origen,
      // Comprimimos un poco para no mandar 8 MB cuando no hace falta.
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
  // Pantalla con stepper que hace el upload + navega al editor.
  await Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ProgresoApunteDesdeFoto(
        imagen: File(picked!.path),
        cursoId: cursoId,
        proyectoId: proyectoId,
        cuadernoId: cuadernoId,
      ),
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

enum _Fase { subiendo, extrayendo, error }

class _ProgresoApunteDesdeFoto extends ConsumerStatefulWidget {
  const _ProgresoApunteDesdeFoto({
    required this.imagen,
    this.cursoId,
    this.proyectoId,
    this.cuadernoId,
  });
  final File imagen;
  final String? cursoId;
  final String? proyectoId;
  final String? cuadernoId;

  @override
  ConsumerState<_ProgresoApunteDesdeFoto> createState() =>
      _ProgresoApunteDesdeFotoState();
}

class _ProgresoApunteDesdeFotoState
    extends ConsumerState<_ProgresoApunteDesdeFoto> {
  _Fase _fase = _Fase.subiendo;
  String? _error;
  late final ApuntesFotoRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = ApuntesFotoRepository();
    // Disparamos el upload en cuanto se monta la pantalla.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ejecutar());
  }

  @override
  void dispose() {
    _repo.close();
    super.dispose();
  }

  Future<void> _ejecutar() async {
    setState(() {
      _fase = _Fase.subiendo;
      _error = null;
    });
    try {
      // El backend hace upload + OCR seguidos sin streamear estados
      // intermedios; aproximamos la transición a "extrayendo" con un
      // tick visual antes del await del response. Es honesto: la
      // espera del await mayoritariamente es OCR.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (mounted) setState(() => _fase = _Fase.extrayendo);

      final resultado = await _repo.subir(
        widget.imagen,
        cursoId: widget.cursoId,
        proyectoId: widget.proyectoId,
        cuadernoId: widget.cuadernoId,
      );
      if (!mounted) return;

      // Refrescamos la lista y abrimos el editor del nuevo apunte.
      ref.invalidate(apuntesListProvider);

      // Cerramos esta pantalla y empujamos el editor.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => EditorApunteScreen(
            apunteId: resultado.apunte.id,
            avisoOcr: resultado.ocrOk ? null : resultado.mensajeOcr,
          ),
        ),
      );
    } on MatixApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _fase = _Fase.error;
        _error = 'Error ${e.statusCode}: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fase = _Fase.error;
        _error = 'No pude completar el apunte: $e';
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
            // Preview de la foto que está subiendo, para que el
            // usuario tenga referencia visual.
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
              activo: _fase == _Fase.subiendo,
              completado: _fase != _Fase.subiendo && _fase != _Fase.error,
              texto: 'Subiendo foto al cerebro…',
            ),
            const SizedBox(height: 12),
            _Paso(
              activo: _fase == _Fase.extrayendo,
              completado: false,
              texto: 'Extrayendo texto con OpenAI vision…',
            ),
            const SizedBox(height: 24),
            if (_fase == _Fase.error) ...[
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
                  _error ?? 'Algo falló.',
                  style: const TextStyle(
                    color: MatixColors.text,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _ejecutar,
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
  const _Paso({
    required this.activo,
    required this.completado,
    required this.texto,
  });
  final bool activo;
  final bool completado;
  final String texto;

  @override
  Widget build(BuildContext context) {
    Widget icono;
    if (completado) {
      icono = const Icon(Icons.check_circle, color: MatixColors.green, size: 22);
    } else if (activo) {
      icono = const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: MatixColors.accent,
        ),
      );
    } else {
      icono = const Icon(
        Icons.radio_button_unchecked,
        color: MatixColors.muted,
        size: 22,
      );
    }
    return Row(
      children: [
        icono,
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 14,
              color: activo || completado
                  ? MatixColors.text
                  : MatixColors.muted,
              fontWeight:
                  activo ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
