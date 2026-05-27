import 'package:flutter/material.dart';

import 'matix_colors.dart';

/// Colores semánticos que no entran en `ColorScheme` de Material 3.
///
/// Se consultan en widgets vía
/// `Theme.of(context).extension<MatixSemanticColors>()!`.
class MatixSemanticColors extends ThemeExtension<MatixSemanticColors> {
  const MatixSemanticColors({
    required this.success,
    required this.warning,
    required this.danger,
    required this.tag,
    required this.cardHi,
    required this.hairline,
    required this.courseSwatches,
  });

  final Color success; // green: completado, OK
  final Color warning; // amber: atención, prioridad media-alta
  final Color danger; // red: borrar, urgente, vencido
  final Color tag; // purple: tags y variante de categoría
  final Color cardHi; // card destacada / estado activo
  final Color hairline; // divisor sutil
  final List<Color> courseSwatches;

  static const dark = MatixSemanticColors(
    success: MatixColors.green,
    warning: MatixColors.amber,
    danger: MatixColors.red,
    tag: MatixColors.purple,
    cardHi: MatixColors.cardHi,
    hairline: MatixColors.hairline,
    courseSwatches: MatixColors.courseSwatches,
  );

  @override
  MatixSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? danger,
    Color? tag,
    Color? cardHi,
    Color? hairline,
    List<Color>? courseSwatches,
  }) {
    return MatixSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      tag: tag ?? this.tag,
      cardHi: cardHi ?? this.cardHi,
      hairline: hairline ?? this.hairline,
      courseSwatches: courseSwatches ?? this.courseSwatches,
    );
  }

  @override
  MatixSemanticColors lerp(ThemeExtension<MatixSemanticColors>? other, double t) {
    if (other is! MatixSemanticColors) return this;
    return MatixSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      tag: Color.lerp(tag, other.tag, t)!,
      cardHi: Color.lerp(cardHi, other.cardHi, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      courseSwatches: courseSwatches, // las swatches no se interpolan
    );
  }
}

extension MatixSemanticColorsOnContext on BuildContext {
  MatixSemanticColors get matixColors =>
      Theme.of(this).extension<MatixSemanticColors>()!;
}
