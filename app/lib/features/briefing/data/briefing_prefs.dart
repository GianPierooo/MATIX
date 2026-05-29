import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias del briefing matutino. Capa 8 reducida · Paso 1.
///
/// Estado de dispositivo (no del hub), por eso shared_preferences en
/// vez de Supabase: la programación de la notificación vive en este
/// teléfono y no tiene sentido fuera de él.
///
/// Defaults: opt-in (activo=false), hora 08:00. Si en el futuro
/// queremos defaults distintos según el dispositivo, esto es el
/// único punto a tocar.
class BriefingPrefs {
  static const _kActivo = 'briefing_activo';
  static const _kHora = 'briefing_hora';
  static const _kMinuto = 'briefing_minuto';

  /// Id estable de la notificación programada con
  /// `flutter_local_notifications`. Distinto de los ids de otros
  /// recordatorios (eventos, tareas, cierre del día) — debe quedar
  /// reservado.
  static const int idNotificacion = 8000001;

  /// Hora por defecto sugerida — 08:00 hora local.
  static const int horaDefault = 8;
  static const int minutoDefault = 0;

  Future<BriefingConfig> leer() async {
    final p = await SharedPreferences.getInstance();
    return BriefingConfig(
      activo: p.getBool(_kActivo) ?? false,
      hora: p.getInt(_kHora) ?? horaDefault,
      minuto: p.getInt(_kMinuto) ?? minutoDefault,
    );
  }

  Future<void> guardar(BriefingConfig c) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kActivo, c.activo);
    await p.setInt(_kHora, c.hora);
    await p.setInt(_kMinuto, c.minuto);
  }
}

class BriefingConfig {
  const BriefingConfig({
    required this.activo,
    required this.hora,
    required this.minuto,
  });

  final bool activo;
  final int hora;
  final int minuto;

  BriefingConfig copyWith({bool? activo, int? hora, int? minuto}) =>
      BriefingConfig(
        activo: activo ?? this.activo,
        hora: hora ?? this.hora,
        minuto: minuto ?? this.minuto,
      );

  String get horaFormateada =>
      '${hora.toString().padLeft(2, '0')}:${minuto.toString().padLeft(2, '0')}';
}
