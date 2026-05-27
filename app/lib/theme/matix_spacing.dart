import 'package:flutter/widgets.dart';

/// Escala de espaciado de Matix.
///
/// Derivada de los pads/gaps más frecuentes en los mockups
/// (base 2px, con énfasis en 8/10/12/14).
class MatixSpacing {
  const MatixSpacing._();

  static const double xs = 2;
  static const double sm = 4;
  static const double s = 6;

  /// Gap default entre elementos relacionados (la mitad de los gaps en
  /// mockups).
  static const double m = 8;
  static const double mPlus = 10;
  static const double l = 12;

  /// Padding horizontal default de pantalla.
  static const double lg = 14;
  static const double xl = 16;
  static const double xl2 = 20;
  static const double xl3 = 24;
  static const double xl4 = 32;
}

/// Helpers de layout sensibles al `MediaQuery`.
class MatixLayout {
  const MatixLayout._();

  /// Padding inferior recomendado para scrollables que viven dentro
  /// del `HomeShell` (Inicio · Proyectos · Tareas · Universidad).
  ///
  /// El `HomeShell` usa `Scaffold(extendBody: true)` para que el
  /// círculo elevado de Matix sobresalga del fondo. Como consecuencia,
  /// el body se dibuja BAJO la nav inferior — si el ListView no
  /// reserva espacio, los últimos ítems quedan tapados.
  ///
  /// Con `extendBody=true`, `Scaffold` inyecta en `MediaQuery.padding.
  /// bottom` la altura de la nav + el safe area del sistema; lo
  /// leemos vía `viewPaddingOf(...)`. Sumamos una constante extra
  /// (~32 px) para cubrir el "saliente" visual del FAB central, que
  /// usa `Transform.translate(-22)` y por eso sobresale por encima
  /// de la nav sin estar contabilizado en su `Size`.
  static double bottomNavGuard(BuildContext ctx) =>
      MediaQuery.viewPaddingOf(ctx).bottom + 32;
}
