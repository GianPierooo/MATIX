import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias del cierre del día. Capa 8 · Paso 2.
///
/// Hermano del `BriefingPrefs`: estado de dispositivo (la
/// programación de la notificación vive en este teléfono), por eso
/// shared_preferences y no Supabase.
///
/// Default: opt-in (activo=false), hora 21:00.
class CierrePrefs {
  static const _kActivo = 'cierre_activo';
  static const _kHora = 'cierre_hora';
  static const _kMinuto = 'cierre_minuto';

  /// Id estable de la notificación, distinto del briefing
  /// (`8000001`) y de los recordatorios de tareas/eventos.
  static const int idNotificacion = 8000002;

  /// Hora por defecto sugerida — 21:00 hora local.
  static const int horaDefault = 21;
  static const int minutoDefault = 0;

  Future<CierreConfig> leer() async {
    final p = await SharedPreferences.getInstance();
    return CierreConfig(
      activo: p.getBool(_kActivo) ?? false,
      hora: p.getInt(_kHora) ?? horaDefault,
      minuto: p.getInt(_kMinuto) ?? minutoDefault,
    );
  }

  Future<void> guardar(CierreConfig c) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kActivo, c.activo);
    await p.setInt(_kHora, c.hora);
    await p.setInt(_kMinuto, c.minuto);
  }
}

class CierreConfig {
  const CierreConfig({
    required this.activo,
    required this.hora,
    required this.minuto,
  });

  final bool activo;
  final int hora;
  final int minuto;

  CierreConfig copyWith({bool? activo, int? hora, int? minuto}) =>
      CierreConfig(
        activo: activo ?? this.activo,
        hora: hora ?? this.hora,
        minuto: minuto ?? this.minuto,
      );

  String get horaFormateada =>
      '${hora.toString().padLeft(2, '0')}:${minuto.toString().padLeft(2, '0')}';
}
