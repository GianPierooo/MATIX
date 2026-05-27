import 'package:flutter/material.dart';

/// Sombras de Matix.
class MatixShadows {
  const MatixShadows._();

  /// Sombra neutra para tarjetas elevadas.
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x4D000000), // rgba(0,0,0,0.30)
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  /// Sombra para botones principales (azul).
  static const List<BoxShadow> button = [
    BoxShadow(
      color: Color(0x4D2D7FF9), // rgba(45,127,249,0.30)
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  /// Sombra reforzada para CTA primaria.
  static const List<BoxShadow> buttonStrong = [
    BoxShadow(
      color: Color(0x592D7FF9), // rgba(45,127,249,0.35)
      blurRadius: 16,
      offset: Offset(0, 6),
    ),
  ];

  /// Sombra del FAB principal, con halo de glow alrededor.
  static const List<BoxShadow> fab = [
    BoxShadow(
      color: Color(0x732D7FF9), // rgba(45,127,249,0.45)
      blurRadius: 28,
      offset: Offset(0, 12),
    ),
    BoxShadow(
      color: Color(0x1A2D7FF9), // rgba(45,127,249,0.10) — halo
      blurRadius: 0,
      spreadRadius: 6,
    ),
  ];

  /// Sombra ascendente para bottom sheets y diálogos modales.
  static const List<BoxShadow> sheet = [
    BoxShadow(
      color: Color(0x80000000), // rgba(0,0,0,0.50)
      blurRadius: 60,
      offset: Offset(0, -20),
    ),
  ];

  /// Sombra verde para CTA de "completar".
  static const List<BoxShadow> success = [
    BoxShadow(
      color: Color(0x4D21D07A), // rgba(33,208,122,0.30)
      blurRadius: 24,
      offset: Offset(0, 10),
    ),
  ];
}
