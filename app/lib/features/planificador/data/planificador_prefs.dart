import 'package:shared_preferences/shared_preferences.dart';

import '../domain/planificador.dart';

/// Preferencia de la ventana de trabajo para planificar el día
/// (Urgencia-3). Estado de dispositivo, como el resto de la config de
/// notificaciones. Default 09:00–21:00.
class PlanificadorPrefs {
  static const _kInicio = 'plan_ventana_inicio';
  static const _kFin = 'plan_ventana_fin';

  Future<VentanaTrabajo> leerVentana() async {
    final p = await SharedPreferences.getInstance();
    return VentanaTrabajo(
      inicio: p.getInt(_kInicio) ?? 9,
      fin: p.getInt(_kFin) ?? 21,
    );
  }

  Future<void> guardarVentana(VentanaTrabajo v) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kInicio, v.inicio);
    await p.setInt(_kFin, v.fin);
  }
}
