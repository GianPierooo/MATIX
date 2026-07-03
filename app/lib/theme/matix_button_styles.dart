import 'package:flutter/material.dart';

import 'matix_colors.dart';

/// Estilos canónicos de botón (E1). Centraliza el `FilledButton.styleFrom(...)`
/// que hoy se repite en decenas de pantallas, para que cambiar el botón primario
/// sea UN solo sitio y no 20+. El LOOK es IDÉNTICO al inline que reemplaza —
/// solo se muta el token, no el aspecto.
///
/// Variantes del primario según el `padding` que ya usaban las pantallas:
///   - [primario]       → padding por defecto de FilledButton.
///   - [primarioAlto]   → CTA de formulario (vertical 16).
///   - [primarioMedio]  → CTA compacto (vertical 14).
class MatixButtonStyles {
  MatixButtonStyles._();

  static ButtonStyle get primario => FilledButton.styleFrom(
        backgroundColor: MatixColors.accent,
        foregroundColor: Colors.white,
      );

  static ButtonStyle get primarioAlto => FilledButton.styleFrom(
        backgroundColor: MatixColors.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
      );

  static ButtonStyle get primarioMedio => FilledButton.styleFrom(
        backgroundColor: MatixColors.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
      );

  /// Destructivo (borrar / desconectar / vaciar): fondo rojo, texto blanco.
  static ButtonStyle get destructivo => FilledButton.styleFrom(
        backgroundColor: MatixColors.red,
        foregroundColor: Colors.white,
      );

  /// Éxito (completar / terminar): fondo verde, texto blanco.
  static ButtonStyle get exito => FilledButton.styleFrom(
        backgroundColor: MatixColors.green,
        foregroundColor: Colors.white,
      );
}
