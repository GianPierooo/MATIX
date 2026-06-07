import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// Detecta y gestiona la EXENCIÓN de optimización de batería del SO.
///
/// CRÍTICO para Honor/MagicOS y otros OEM agresivos: si el sistema decide
/// "ahorrar batería" matando a Matix, los pushes de FCM pueden retrasarse
/// horas y los handlers de tap de background (botones de acción) pueden NO
/// dispararse. Pedir la exención sube mucho la confiabilidad.
///
/// En iOS / Android < 6 no aplica → devuelve `true` (exenta) directamente.
class EntregaBackgroundService {
  /// `true` si la app ya está EXENTA de la optimización (o si no aplica).
  /// `false` si Android está optimizándola — es ahí donde hay que guiar.
  Future<bool> exenta() async {
    if (!Platform.isAndroid) return true;
    try {
      final s = await Permission.ignoreBatteryOptimizations.status;
      return s.isGranted;
    } catch (_) {
      // El permiso puede no estar declarado en algunas builds; lo tratamos
      // como "no exenta" para guiar al usuario.
      return false;
    }
  }

  /// Abre el diálogo del sistema para que el usuario conceda la exención.
  /// Devuelve `true` si quedó concedida tras el diálogo. Best-effort: si el
  /// fabricante no permite el diálogo directo (algunos OEM lo bloquean),
  /// abre los ajustes generales de batería para que el usuario lo haga manual.
  Future<bool> pedirExencion() async {
    if (!Platform.isAndroid) return true;
    try {
      final r = await Permission.ignoreBatteryOptimizations.request();
      if (r.isGranted) return true;
    } catch (_) {
      // Cae al openAppSettings.
    }
    // Fallback honesto: lo llevamos a Ajustes de la app (de ahí el usuario
    // navega a "Batería" → "Sin restricciones").
    try {
      await openAppSettings();
    } catch (_) {}
    return false;
  }
}

final entregaBackgroundServiceProvider = Provider<EntregaBackgroundService>(
  (_) => EntregaBackgroundService(),
);

/// Estado de exención: `true` exenta, `false` optimizada, `null` cargando.
final exencionBateriaProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.read(entregaBackgroundServiceProvider).exenta(),
);
