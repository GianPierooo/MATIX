import 'package:shared_preferences/shared_preferences.dart';

import '../domain/disponibilidad.dart';

/// Persiste la disponibilidad POR DÍA (Fase 3). Estado de dispositivo,
/// como el resto de la config de notificaciones. Default: todos los días
/// 09:00–21:00; el usuario lo afina por día.
///
/// Se guarda por día ISO (1..7) con tres claves: activo / inicio / fin.
class PlanificadorPrefs {
  String _kActivo(int d) => 'disp_${d}_activo';
  String _kInicio(int d) => 'disp_${d}_inicio';
  String _kFin(int d) => 'disp_${d}_fin';

  Future<DisponibilidadSemanal> leerDisponibilidad() async {
    final p = await SharedPreferences.getInstance();
    final porDefecto = DisponibilidadSemanal.porDefecto;
    final mapa = <int, DisponibilidadDia>{};
    for (var d = 1; d <= 7; d++) {
      final def = porDefecto.diaDe(d);
      mapa[d] = DisponibilidadDia(
        activo: p.getBool(_kActivo(d)) ?? def.activo,
        inicio: p.getInt(_kInicio(d)) ?? def.inicio,
        fin: p.getInt(_kFin(d)) ?? def.fin,
      );
    }
    return DisponibilidadSemanal(mapa);
  }

  Future<void> guardarDisponibilidad(DisponibilidadSemanal disp) async {
    final p = await SharedPreferences.getInstance();
    for (var d = 1; d <= 7; d++) {
      final dia = disp.diaDe(d);
      await p.setBool(_kActivo(d), dia.activo);
      await p.setInt(_kInicio(d), dia.inicio);
      await p.setInt(_kFin(d), dia.fin);
    }
  }
}
