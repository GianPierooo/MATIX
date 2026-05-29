import 'package:flutter/material.dart';

import '../../../theme/matix_colors.dart';
import '../../../theme/matix_spacing.dart';
import '../../../theme/matix_typography.dart';
import 'captura_camara_screen.dart';

/// Muestra el texto que extrajo el OCR en un campo **editable**, para
/// que el usuario corrija lo que ML Kit haya errado (Capa 7-A).
///
/// La edición vive acá como estado local del `TextEditingController`.
/// En 7-A esto es el final del flujo: solo capturar y dejar el texto
/// editable. Mandarlo al cerebro y convertirlo en tareas es 7-B.
///
/// Si [aviso] viene con texto (OCR vacío, falló, o cámara no
/// disponible), pintamos un banner ámbar y el campo arranca vacío para
/// escribir a mano. Nunca se cierra en silencio.
class ResultadoOcrScreen extends StatefulWidget {
  const ResultadoOcrScreen({
    super.key,
    required this.textoInicial,
    this.aviso,
  });

  final String textoInicial;
  final String? aviso;

  @override
  State<ResultadoOcrScreen> createState() => _ResultadoOcrScreenState();
}

class _ResultadoOcrScreenState extends State<ResultadoOcrScreen> {
  late final TextEditingController _texto;

  @override
  void initState() {
    super.initState();
    _texto = TextEditingController(text: widget.textoInicial);
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

  @override
  Widget build(BuildContext context) {
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
              Text(
                'Por ahora Matix solo extrae el texto. Convertirlo en '
                'tareas llega en el siguiente paso.',
                style: MatixText.small,
              ),
              const SizedBox(height: MatixSpacing.l),
              OutlinedButton.icon(
                onPressed: _capturarOtra,
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
