import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'matix_colors.dart';

/// Tipografía de Matix.
///
/// Inter para UI, JetBrains Mono para bloques de código en Apuntes.
/// Estos `TextStyle` ya traen color por defecto; se pueden overrride
/// con `.copyWith(color: ...)`.
class MatixText {
  const MatixText._();

  static TextStyle _inter({
    required double size,
    required FontWeight weight,
    Color color = MatixColors.text,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  // 26 — heros (Detalle Curso, Inicio)
  static TextStyle display = _inter(size: 26, weight: FontWeight.w700, height: 1.15);

  // 22 — títulos de pantalla
  static TextStyle title = _inter(size: 22, weight: FontWeight.w700, height: 1.2);

  // 18 — subtítulos de sección
  static TextStyle subtitle = _inter(size: 18, weight: FontWeight.w600, height: 1.25);

  // 15 — body con jerarquía
  static TextStyle bodyLg = _inter(size: 15, weight: FontWeight.w500, height: 1.4);

  // 14 — body por defecto
  static TextStyle body = _inter(size: 14, weight: FontWeight.w500, height: 1.4);

  // 12 — texto secundario, metadata
  static TextStyle small =
      _inter(size: 12, weight: FontWeight.w500, color: MatixColors.muted, height: 1.35);

  // 11 — micro: captions, contadores
  static TextStyle micro =
      _inter(size: 11, weight: FontWeight.w600, color: MatixColors.muted, height: 1.3);

  // 10 — caption muy pequeño
  static TextStyle caption =
      _inter(size: 10, weight: FontWeight.w600, color: MatixColors.muted, height: 1.3);

  // Mono para bloques de código en Apuntes.
  static TextStyle mono({double size = 13, FontWeight weight = FontWeight.w500}) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
      color: MatixColors.text,
      height: 1.45,
    );
  }
}

/// `TextTheme` para `ThemeData` — alimenta a widgets de Material que leen
/// del theme (AppBar, ListTile, etc.). Usa la misma fuente que `MatixText`.
TextTheme buildMatixTextTheme() {
  return TextTheme(
    displayMedium: MatixText.display,
    headlineSmall: MatixText.title,
    titleLarge: MatixText.title,
    titleMedium: MatixText.subtitle,
    bodyLarge: MatixText.bodyLg,
    bodyMedium: MatixText.body,
    bodySmall: MatixText.small,
    labelLarge: MatixText.body.copyWith(fontWeight: FontWeight.w600),
    labelMedium: MatixText.small,
    labelSmall: MatixText.micro,
  );
}
