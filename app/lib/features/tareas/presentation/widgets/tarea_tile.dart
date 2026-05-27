import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../theme/matix_colors.dart';
import '../../domain/tarea.dart';

class TareaTile extends StatelessWidget {
  const TareaTile({
    super.key,
    required this.tarea,
    required this.onToggleCompletada,
    required this.onTap,
    this.metaSecundaria,
  });

  final Tarea tarea;
  final ValueChanged<bool> onToggleCompletada;
  final VoidCallback onTap;

  /// Texto adicional bajo el título (ej. el curso, la categoría).
  /// Si es null, se omite.
  final String? metaSecundaria;

  @override
  Widget build(BuildContext context) {
    final color = _colorPrioridad(tarea.prioridad);
    final vencida = tarea.estaVencida;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: vencida
            ? MatixColors.red.withValues(alpha: 0.10)
            : MatixColors.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Checkbox(
                  completada: tarea.completada,
                  onChanged: onToggleCompletada,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              tarea.titulo,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: tarea.completada
                                    ? MatixColors.muted
                                    : MatixColors.text,
                                decoration: tarea.completada
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                                height: 1.25,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          if (metaSecundaria != null) ...[
                            _Chip(
                              text: metaSecundaria!,
                              color: MatixColors.muted,
                            ),
                            const SizedBox(width: 8),
                          ],
                          _VenceLabel(tarea: tarea),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({required this.completada, required this.onChanged});
  final bool completada;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!completada),
      child: Container(
        width: 22,
        height: 22,
        margin: const EdgeInsets.only(top: 1),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: completada ? MatixColors.green : Colors.transparent,
          border: completada
              ? null
              : Border.all(
                  color: Colors.white.withValues(alpha: 0.18),
                  width: 1.8,
                ),
        ),
        child: completada
            ? const Icon(Icons.check, size: 14, color: MatixColors.bg)
            : null,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _VenceLabel extends StatelessWidget {
  const _VenceLabel({required this.tarea});
  final Tarea tarea;

  @override
  Widget build(BuildContext context) {
    final v = tarea.venceEn;
    if (v == null) {
      return const Row(
        children: [
          Icon(Icons.schedule, size: 12, color: MatixColors.muted),
          SizedBox(width: 4),
          Text(
            '—',
            style: TextStyle(
              fontSize: 12,
              color: MatixColors.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }
    final local = v.toLocal();
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final dia = DateTime(local.year, local.month, local.day);
    final diff = dia.difference(hoy).inDays;
    String texto;
    if (diff == 0) {
      texto = 'Hoy · ${DateFormat.Hm().format(local)}';
    } else if (diff == 1) {
      texto = 'Mañana · ${DateFormat.Hm().format(local)}';
    } else if (diff > 1 && diff < 7) {
      texto =
          '${DateFormat.E('es').format(local).toUpperCase()} · ${DateFormat.Hm().format(local)}';
    } else {
      texto = DateFormat('d MMM · HH:mm', 'es').format(local);
    }
    final color = tarea.estaVencida ? MatixColors.red : MatixColors.muted;
    return Row(
      children: [
        Icon(Icons.schedule, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          texto,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

Color _colorPrioridad(Prioridad p) => switch (p) {
      Prioridad.alta => MatixColors.red,
      Prioridad.media => MatixColors.amber,
      Prioridad.baja => MatixColors.accent,
    };
