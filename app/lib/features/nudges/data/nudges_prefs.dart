import 'package:shared_preferences/shared_preferences.dart';

import '../domain/nudges.dart';

/// Preferencias de los nudges escalados (Capa 7 · Urgencia-2).
///
/// Estado de dispositivo (no del hub) — igual que el briefing y el
/// cierre: la programación de notificaciones vive en este teléfono.
/// Guarda la intensidad global, la ventana de silencio, y el conjunto
/// de tareas con nudges apagados.
///
/// Defaults: intensidad normal, silencio 22:00–08:00, ninguna tarea
/// silenciada.
class NudgesConfig {
  const NudgesConfig({
    this.intensidad = IntensidadNudge.normal,
    this.silencio = const HorasSilencio(),
  });

  final IntensidadNudge intensidad;
  final HorasSilencio silencio;

  NudgesConfig copyWith({IntensidadNudge? intensidad, HorasSilencio? silencio}) =>
      NudgesConfig(
        intensidad: intensidad ?? this.intensidad,
        silencio: silencio ?? this.silencio,
      );
}

class NudgesPrefs {
  static const _kIntensidad = 'nudges_intensidad';
  static const _kSilencioInicio = 'nudges_silencio_inicio';
  static const _kSilencioFin = 'nudges_silencio_fin';
  static const _kSilenciadas = 'nudges_silenciadas';

  Future<NudgesConfig> leerConfig() async {
    final p = await SharedPreferences.getInstance();
    return NudgesConfig(
      intensidad: IntensidadNudge.fromJson(p.getString(_kIntensidad)),
      silencio: HorasSilencio(
        inicio: p.getInt(_kSilencioInicio) ?? 22,
        fin: p.getInt(_kSilencioFin) ?? 8,
      ),
    );
  }

  Future<void> guardarConfig(NudgesConfig c) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kIntensidad, c.intensidad.toJson());
    await p.setInt(_kSilencioInicio, c.silencio.inicio);
    await p.setInt(_kSilencioFin, c.silencio.fin);
  }

  /// ¿Esta tarea tiene los nudges apagados?
  Future<bool> estaSilenciada(String tareaId) async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_kSilenciadas) ?? const []).contains(tareaId);
  }

  /// Apaga (o reactiva) los nudges de una tarea puntual.
  Future<void> setSilenciada(String tareaId, bool silenciada) async {
    final p = await SharedPreferences.getInstance();
    final actual = (p.getStringList(_kSilenciadas) ?? const <String>[]).toSet();
    if (silenciada) {
      actual.add(tareaId);
    } else {
      actual.remove(tareaId);
    }
    await p.setStringList(_kSilenciadas, actual.toList());
  }
}
