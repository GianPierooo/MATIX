import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'matix_colors.dart';
import 'matix_radii.dart';
import 'matix_semantic_colors.dart';
import 'matix_typography.dart';

/// `ThemeData` de Matix.
///
/// Capa 1: solo dark theme (los mockups así están). Light theme se
/// considera si el usuario lo pide explícitamente.
ThemeData buildMatixTheme() {
  const colorScheme = ColorScheme.dark(
    surface: MatixColors.bg,
    surfaceContainer: MatixColors.card,
    surfaceContainerHigh: MatixColors.cardHi,
    onSurface: MatixColors.text,
    onSurfaceVariant: MatixColors.muted,
    outlineVariant: MatixColors.hairline,
    primary: MatixColors.accent,
    onPrimary: Colors.white,
    secondary: MatixColors.purple,
    onSecondary: Colors.white,
    error: MatixColors.red,
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: MatixColors.bg,
    textTheme: buildMatixTextTheme(),
    appBarTheme: const AppBarTheme(
      backgroundColor: MatixColors.bg,
      foregroundColor: MatixColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: MatixColors.bg,
      indicatorColor: MatixColors.cardHi,
      labelTextStyle: WidgetStatePropertyAll(MatixText.micro),
      iconTheme: const WidgetStatePropertyAll(IconThemeData(color: MatixColors.text)),
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: const CardThemeData(
      color: MatixColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: MatixRadii.brMd),
    ),
    extensions: const [MatixSemanticColors.dark],
  );
}
