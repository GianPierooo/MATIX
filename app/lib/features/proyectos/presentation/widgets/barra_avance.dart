import 'package:flutter/material.dart';

import '../../../../theme/matix_colors.dart';

/// Barra de % de avance de un proyecto (perfil profundo · % de avance).
///
/// El número lo calcula el cerebro desde el árbol (ponderado por fase); acá solo
/// se pinta. Tono de aliento honesto: color cálido al arrancar, verde al cerrar.
class BarraAvance extends StatelessWidget {
  const BarraAvance({super.key, required this.porcentaje});

  /// 0..100.
  final int porcentaje;

  @override
  Widget build(BuildContext context) {
    final pct = porcentaje.clamp(0, 100);
    final color = pct >= 80
        ? MatixColors.green
        : pct >= 40
            ? MatixColors.accent
            : MatixColors.amber;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'AVANCE',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: MatixColors.muted,
              ),
            ),
            Text(
              '$pct%',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct / 100,
            minHeight: 7,
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
