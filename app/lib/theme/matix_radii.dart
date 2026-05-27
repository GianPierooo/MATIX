import 'package:flutter/material.dart';

/// Radios de Matix.
class MatixRadii {
  const MatixRadii._();

  static const double xs = 8;
  static const double sm = 10;

  /// Default: cards y botones.
  static const double md = 12;
  static const double lg = 14;

  /// Modales, bottom sheets y FAB grandes.
  static const double xl = 18;
  static const double pill = 999;

  static const BorderRadius brXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius brSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius brXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius brPill = BorderRadius.all(Radius.circular(pill));
}
