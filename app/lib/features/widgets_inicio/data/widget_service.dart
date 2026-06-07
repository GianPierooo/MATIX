import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';

import '../../../api/matix_client.dart';
import '../../horario/data/horario_repository.dart';
import '../../horario/domain/plan_dia.dart';
import '../domain/widget_datos.dart';

/// Puente app → widgets de pantalla de inicio ("Próximo" y "Hoy").
///
/// La app EMPUJA aquí el plan del día (ya determinista) al almacenamiento del
/// widget y dispara el refresco. El widget nativo (RemoteViews) solo lee esas
/// claves y pinta — sin lógica de negocio ni llamadas al cerebro desde el
/// nativo. Best-effort: el widget JAMÁS rompe la app (todo en try/catch).
class WidgetService {
  // Nombres de las clases AppWidgetProvider en Kotlin (ver android/).
  static const _proximoProvider = 'ProximoWidgetProvider';
  static const _hoyProvider = 'HoyWidgetProvider';

  // Tarea periódica de WorkManager (refresco en background).
  static const tareaRefresco = 'matix-widget-refresco';
  static const _frecuencia = Duration(minutes: 90);

  /// Empuja el plan al widget y refresca ambos. La SELECCIÓN es pura
  /// (`construirDatosWidget`); aquí solo persistimos + disparamos el update.
  static Future<void> actualizar(PlanDia? plan, DateTime ahora) async {
    try {
      final d = construirDatosWidget(plan, ahora);
      await _guardar(d);
      await HomeWidget.updateWidget(androidName: _proximoProvider);
      await HomeWidget.updateWidget(androidName: _hoyProvider);
    } catch (e) {
      debugPrint('Widget: no pude actualizar ($e).');
    }
  }

  static Future<void> _guardar(DatosWidget d) async {
    Future<void> s(String k, String v) =>
        HomeWidget.saveWidgetData<String>(k, v);

    await s('vacio', d.vacio ? '1' : '0');
    await s('sin_pendientes', d.sinPendientes ? '1' : '0');
    await s('fecha', d.fecha);
    await s('actualizado', d.actualizado);

    // Próximo (una sola cosa, glanceable).
    final p = d.proximo;
    await s('prox_hay', p == null ? '0' : '1');
    await s('prox_hora', p?.hora ?? '');
    await s('prox_titulo', p?.titulo ?? '');
    await s('prox_sub', p?.sub ?? '');
    await s('prox_rel', d.proximoRel);
    await s('prox_color', p?.colorHex ?? '#2D7FF9');
    await s('prox_fijo', (p?.fijo ?? false) ? '1' : '0');
    await s('prox_payload', p?.payload ?? 'hoy');

    // Hoy (lista capada + overflow). El "+X más" lo arma el nativo combinando
    // este overflow con las filas que oculte por tamaño del widget.
    await s('hoy_count', d.hoy.length.toString());
    for (var i = 0; i < d.hoy.length; i++) {
      final it = d.hoy[i];
      await s('hoy_${i}_hora', it.hora);
      await s('hoy_${i}_titulo', it.titulo);
      await s('hoy_${i}_sub', it.sub);
      await s('hoy_${i}_rel', i == 0 ? d.proximoRel : '');
      await s('hoy_${i}_color', it.colorHex);
      await s('hoy_${i}_fijo', it.fijo ? '1' : '0');
      await s('hoy_${i}_payload', it.payload);
    }
    await s('hoy_overflow_n', d.overflow.toString());
  }

  /// Registra el refresco periódico en background (WorkManager). Intervalo
  /// sensato (90 min) y solo con red — no agresivo, cuida batería. Best-effort:
  /// si WorkManager no está disponible, la app sigue (el push on-change cubre el
  /// caso app-abierta). Solo Android.
  static Future<void> registrarRefrescoPeriodico() async {
    if (!Platform.isAndroid) return;
    try {
      await Workmanager().initialize(widgetWorkmanagerDispatcher);
      await Workmanager().registerPeriodicTask(
        tareaRefresco,
        tareaRefresco,
        frequency: _frecuencia,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (e) {
      debugPrint('Widget: no pude registrar el refresco periódico ($e).');
    }
  }
}

/// Callback de WorkManager (isolate de background, sin Riverpod). Re-trae el
/// plan del cerebro (determinista) y lo empuja al widget. TOP-LEVEL con
/// `@pragma('vm:entry-point')` para que el isolate lo invoque. Nunca lanza.
@pragma('vm:entry-point')
void widgetWorkmanagerDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final plan = await HorarioRepository(MatixClient()).cargar();
      await WidgetService.actualizar(plan, DateTime.now());
    } catch (e) {
      debugPrint('Widget BG: refresco falló ($e).');
    }
    return true;
  });
}
