import 'package:flutter/material.dart';

import '../../../../theme/matix_colors.dart';
import '../../../../theme/matix_spacing.dart';
import '../../../../theme/matix_typography.dart';
import '../../data/matix_chat_repository.dart';

/// Bloque interactivo de opciones tocables (elicitación, estilo Claude) que va
/// debajo del último mensaje de Matix:
/// - `seleccion_unica`: chips; tocar uno responde.
/// - `seleccion_multiple`: chips toggle + botón Enviar (responde la lista).
/// - `texto`: un campo para escribir + enviar.
///
/// Tocar/enviar llama a [onResponder] con el texto, que el chat manda como el
/// siguiente mensaje del usuario. No rompe el flujo normal: el composer sigue
/// disponible y `onResponder` usa el mismo `enviar` de siempre.
class OpcionesInteractivas extends StatefulWidget {
  const OpcionesInteractivas({
    super.key,
    required this.bloque,
    required this.enabled,
    required this.onResponder,
  });

  final BloqueOpciones bloque;
  final bool enabled;
  final void Function(String texto) onResponder;

  @override
  State<OpcionesInteractivas> createState() => _OpcionesInteractivasState();
}

class _OpcionesInteractivasState extends State<OpcionesInteractivas> {
  final Set<String> _seleccion = {};
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _responder(String t) {
    if (!widget.enabled) return;
    widget.onResponder(t);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bloque;
    return Padding(
      padding: const EdgeInsets.only(top: MatixSpacing.s, left: 2, right: 2),
      child: b.esTexto ? _campoTexto() : _chips(b),
    );
  }

  Widget _chips(BloqueOpciones b) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: MatixSpacing.s,
          runSpacing: MatixSpacing.s,
          children: [
            for (final o in b.opciones)
              _Chip(
                texto: o,
                activo: b.esMultiple && _seleccion.contains(o),
                enabled: widget.enabled,
                onTap: () {
                  if (b.esMultiple) {
                    setState(() => _seleccion.contains(o)
                        ? _seleccion.remove(o)
                        : _seleccion.add(o));
                  } else {
                    _responder(o); // selección única: responde al toque
                  }
                },
              ),
          ],
        ),
        if (b.esMultiple) ...[
          const SizedBox(height: MatixSpacing.s),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: (widget.enabled && _seleccion.isNotEmpty)
                  ? () => _responder(
                      b.opciones.where(_seleccion.contains).join(', '))
                  : null,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                    horizontal: MatixSpacing.xl, vertical: MatixSpacing.s),
              ),
              child: const Text('Enviar'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _campoTexto() {
    void enviar() {
      final t = _ctrl.text.trim();
      if (t.isEmpty) return;
      _ctrl.clear();
      _responder(t);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: MatixColors.card,
              border: Border.all(color: MatixColors.hairline),
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextField(
              controller: _ctrl,
              enabled: widget.enabled,
              style: MatixText.body,
              minLines: 1,
              maxLines: 4,
              onSubmitted: (_) => enviar(),
              decoration: InputDecoration(
                hintText: 'Escribe tu respuesta…',
                hintStyle: MatixText.small,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: MatixSpacing.l, vertical: MatixSpacing.m),
              ),
            ),
          ),
        ),
        const SizedBox(width: MatixSpacing.s),
        IconButton(
          onPressed: widget.enabled ? enviar : null,
          icon: const Icon(Icons.send_rounded, color: MatixColors.accent),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.texto,
    required this.activo,
    required this.enabled,
    required this.onTap,
  });
  final String texto;
  final bool activo;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: activo
          ? MatixColors.accent
          : MatixColors.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: activo ? Colors.white : MatixColors.accent,
            ),
          ),
        ),
      ),
    );
  }
}
