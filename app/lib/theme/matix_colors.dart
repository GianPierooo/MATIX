import 'package:flutter/material.dart';

/// Paleta cruda de Matix (dark theme).
///
/// La paleta se extrae de los mockups y se valida en `docs/ESTADO.md`.
/// No usar directamente desde widgets de pantalla salvo cuando se necesita
/// un color que no encaja en `ColorScheme` ni en `MatixSemanticColors`.
class MatixColors {
  const MatixColors._();

  // Superficies
  static const Color bg = Color(0xFF0B0F1A);
  static const Color card = Color(0xFF161B2E);
  static const Color cardHi = Color(0xFF1B2138);

  // Texto
  static const Color text = Color(0xFFE8ECF4);
  static const Color muted = Color(0xFF8A93A8);

  // Hairline (divisores muy sutiles, rgba(255,255,255,0.06))
  static const Color hairline = Color(0x0FFFFFFF);

  // Acentos semánticos
  static const Color accent = Color(0xFF2D7FF9);
  static const Color green = Color(0xFF21D07A);
  static const Color red = Color(0xFFFF4D5E);
  static const Color amber = Color(0xFFE0A33A);
  static const Color purple = Color(0xFF9B7BFF);
  static const Color pink = Color(0xFFF06EA9);
  static const Color teal = Color(0xFF3CCFCF);

  // Colores disponibles para asignar a un curso / categoría.
  static const List<Color> courseSwatches = [
    accent,
    green,
    red,
    amber,
    purple,
    pink,
    teal,
  ];
}
