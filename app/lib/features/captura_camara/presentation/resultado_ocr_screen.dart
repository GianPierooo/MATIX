import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/matix_colors.dart';
import '../../../theme/matix_spacing.dart';
import '../../../theme/matix_typography.dart';
import '../application/extraccion_tareas_controller.dart';
import 'captura_camara_screen.dart';
import 'revision_tareas_screen.dart';

/// Muestra el texto que extrajo el OCR en un campo **editable**, para
/// que el usuario corrija lo que ML Kit haya errado (Capa 7-A) y, con
/// el botón "Convertir en tareas", lo mande al cerebro para extraer
/// tareas que revisa y crea (Capa 7-B).
///
/// La edición vive acá como estado local del `TextEditingController`.
/// SOLO el texto (ya corregido) viaja al cerebro: la imagen se quedó
/// en el teléfono (7-A).
///
/// Si [aviso] viene con texto (OCR vacío, falló, o cámara no
/// disponible), pintamos un banner ámbar y el campo arranca vacío para
/// escribir a mano. Nunca se cierra en silencio.
class ResultadoOcrScreen extends ConsumerStatefulWidget {
  const ResultadoOcrScreen({
    super.key,
    required this.textoInicial,
    this.aviso,
  });

  final String textoInicial;
  final String? aviso;

  @override
  ConsumerState<ResultadoOcrScreen> createState() =>
      _ResultadoOcrScreenState();
}

class _ResultadoOcrScreenState extends ConsumerState<ResultadoOcrScreen> {
  late final TextEditingController _texto;

  @override
  void initState() {
    super.initState();
    _texto = TextEditingController(text: widget.textoInicial);
    // Arrancamos el flujo de extracción limpio: si quedó estado de una
    // captura anterior, lo reseteamos para que el `ref.listen` no
    // dispare una navegación fantasma al montar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(extraccionTareasControllerProvider.notifier).reiniciar();
    });
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  void _capturarOtra() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CapturaCamaraScreen()),
    );
  }

  void _convertir() {
    ref
        .read(extraccionTareasControllerProvider.notifier)
        .interpretar(_texto.text);
  }

  @override
  Widget build(BuildContext context) {
    // Cuando el cerebro responde, saltamos a la hoja de revisión. Si
    // falla, mostramos el error y dejamos reintentar (el botón sigue).
    ref.listen<EstadoExtraccion>(extraccionTareasControllerProvider,
        (prev, next) {
      if (prev?.fase == next.fase) return;
      if (next.fase == FaseExtraccion.revision) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RevisionTareasScreen()),
        );
      } else if (next.fase == FaseExtraccion.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error ?? 'No pude convertir el texto.'),
            action: SnackBarAction(label: 'Reintentar', onPressed: _convertir),
          ),
        );
      }
    });

    final interpretando =
        ref.watch(extraccionTareasControllerProvider).fase ==
            FaseExtraccion.interpretando;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Texto extraído'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MatixSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.aviso != null) ...[
                _AvisoBanner(mensaje: widget.aviso!),
                const SizedBox(height: MatixSpacing.l),
              ],
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(MatixSpacing.l),
                  decoration: BoxDecoration(
                    color: MatixColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: MatixColors.hairline),
                  ),
                  child: TextField(
                    controller: _texto,
                    autofocus: widget.aviso != null,
                    maxLines: null,
                    minLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    style: MatixText.body.copyWith(height: 1.5),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'El texto extraído aparece aquí. Edítalo '
                          'para corregir lo que el OCR haya errado.',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: MatixSpacing.l),
              FilledButton.icon(
                onPressed: interpretando ? null : _convertir,
                icon: interpretando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white),
                      )
                    : const Icon(Icons.checklist_outlined, size: 18),
                label: Text(
                    interpretando ? 'Convirtiendo…' : 'Convertir en tareas'),
                style: FilledButton.styleFrom(
                  backgroundColor: MatixColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: MatixSpacing.m),
              OutlinedButton.icon(
                onPressed: interpretando ? null : _capturarOtra,
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: const Text('Capturar otra'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MatixColors.text,
                  side: const BorderSide(color: MatixColors.hairline),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvisoBanner extends StatelessWidget {
  const _AvisoBanner({required this.mensaje});
  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MatixSpacing.l),
      decoration: BoxDecoration(
        color: MatixColors.amber.withValues(alpha: 0.12),
        border: Border.all(color: MatixColors.amber.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: MatixColors.amber, size: 18),
          const SizedBox(width: MatixSpacing.m),
          Expanded(
            child: Text(mensaje, style: MatixText.small.copyWith(
              color: MatixColors.text,
            )),
          ),
        ],
      ),
    );
  }
}
