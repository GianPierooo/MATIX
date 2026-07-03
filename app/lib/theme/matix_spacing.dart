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

  // Valores puntuales de pantallas concretas, tokenizados con su valor EXACTO
  // (elimina números mágicos sin cambiar el look). Nombre = valor en px.
  static const double s18 = 18;
  static const double s22 = 22;
  static const double s26 = 26;
  static const double s28 = 28;
  static const double s36 = 36;
  static const double s40 = 40;
  static const double s42 = 42;
}

/// Convención ÚNICA de scroll de Matix: el inset inferior que TODA pantalla
/// scrolleable debe reservar para que el último ítem nunca quede tapado por la
/// barra de navegación ni por el robot flotante. Aplícala SIEMPRE (o usa
/// [PantallaScroll], que ya la hereda). Pantalla nueva = hereda esto y el bug
/// no vuelve.
///
/// La fórmula es la del prompt: insets del sistema (gesto/barra) + alto de la
/// barra de navegación inferior + holgura (+ robot si aplica).
class MatixLayout {
  const MatixLayout._();

  /// Alto aproximado de la barra de navegación inferior del HomeShell (sin el
  /// safe area del sistema, que se cuenta aparte vía `viewPadding`). El
  /// `_MatixBottomNav` mide ~64 px de contenido (iconos + labels + padding).
  static const double alturaBarraNav = 64;

  /// Holgura visual mínima: el "saliente" del FAB central (`Transform.translate
  /// (-22)`) + aire para que no quede pegado.
  static const double holgura = 12;

  /// Espacio para el robot flotante (PresenciaMatix, tarjeta expandida). Solo
  /// Inicio lo necesita; el resto de pantallas no monta ese robot.
  static const double holguraRobot = 200;

  /// Inset inferior CANÓNICO para cualquier scrollable.
  ///
  /// El `HomeShell` usa `Scaffold(extendBody: true)` (para que el círculo
  /// elevado de Matix sobresalga), así que el body se dibuja BAJO la barra
  /// inferior: sin este colchón, los últimos ítems quedan tapados. Antes el
  /// guard solo sumaba el `viewPadding` del sistema (~gesto) + 32 y se OLVIDABA
  /// el alto de la barra (~64) — por eso se cortaba (p. ej. el domingo en el
  /// calendario semanal). Ahora lo incluye explícito. `conRobot` añade el
  /// espacio del robot flotante (Inicio).
  static double scrollBottom(BuildContext ctx, {bool conRobot = false}) =>
      MediaQuery.viewPaddingOf(ctx).bottom +
      alturaBarraNav +
      holgura +
      (conRobot ? holguraRobot : 0);

  /// Alias histórico (sin robot). Equivale a `scrollBottom(ctx)`. Mantiene el
  /// nombre que ya usan varias pantallas.
  static double bottomNavGuard(BuildContext ctx) => scrollBottom(ctx);
}
