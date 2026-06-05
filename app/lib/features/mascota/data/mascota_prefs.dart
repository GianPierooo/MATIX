import 'package:shared_preferences/shared_preferences.dart';

import '../domain/dosificacion.dart';

/// Estado de dispositivo de la mascota (no del hub): on/off, frecuencia, horas
/// de silencio, marcas de tiempo (saludo/aparición/despedida) y la racha de
/// veces que la ignoraste (para bajar el volumen). Defaults: ON, normal,
/// silencio 22:00–08:00.
class MascotaConfig {
  const MascotaConfig({
    this.habilitada = true,
    this.frecuencia = FrecuenciaMascota.normal,
    this.silencioInicio = 22,
    this.silencioFin = 8,
  });

  final bool habilitada;
  final FrecuenciaMascota frecuencia;
  final int silencioInicio;
  final int silencioFin;

  MascotaConfig copyWith({
    bool? habilitada,
    FrecuenciaMascota? frecuencia,
    int? silencioInicio,
    int? silencioFin,
  }) =>
      MascotaConfig(
        habilitada: habilitada ?? this.habilitada,
        frecuencia: frecuencia ?? this.frecuencia,
        silencioInicio: silencioInicio ?? this.silencioInicio,
        silencioFin: silencioFin ?? this.silencioFin,
      );
}

class MascotaPrefs {
  static const _kHabilitada = 'mascota_habilitada';
  static const _kFrecuencia = 'mascota_frecuencia';
  static const _kSilencioInicio = 'mascota_silencio_inicio';
  static const _kSilencioFin = 'mascota_silencio_fin';
  static const _kUltimoSaludo = 'mascota_ultimo_saludo_ms';
  static const _kUltimaAparicion = 'mascota_ultima_aparicion_ms';
  static const _kUltimaDespedida = 'mascota_ultima_despedida_ms';
  static const _kIgnoradas = 'mascota_ignoradas_seguidas';

  Future<MascotaConfig> leerConfig() async {
    final p = await SharedPreferences.getInstance();
    return MascotaConfig(
      habilitada: p.getBool(_kHabilitada) ?? true,
      frecuencia: frecuenciaDe(p.getString(_kFrecuencia)),
      silencioInicio: p.getInt(_kSilencioInicio) ?? 22,
      silencioFin: p.getInt(_kSilencioFin) ?? 8,
    );
  }

  Future<void> guardarConfig(MascotaConfig c) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kHabilitada, c.habilitada);
    await p.setString(_kFrecuencia, c.frecuencia.id);
    await p.setInt(_kSilencioInicio, c.silencioInicio);
    await p.setInt(_kSilencioFin, c.silencioFin);
  }

  Future<DateTime?> _leerMarca(String k) async {
    final p = await SharedPreferences.getInstance();
    final ms = p.getInt(k);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> _guardarMarca(String k, DateTime t) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(k, t.millisecondsSinceEpoch);
  }

  Future<DateTime?> ultimoSaludo() => _leerMarca(_kUltimoSaludo);
  Future<void> marcarSaludo(DateTime t) => _guardarMarca(_kUltimoSaludo, t);

  Future<DateTime?> ultimaAparicion() => _leerMarca(_kUltimaAparicion);
  Future<void> marcarAparicion(DateTime t) => _guardarMarca(_kUltimaAparicion, t);

  Future<DateTime?> ultimaDespedida() => _leerMarca(_kUltimaDespedida);
  Future<void> marcarDespedida(DateTime t) => _guardarMarca(_kUltimaDespedida, t);

  Future<int> ignoradasSeguidas() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kIgnoradas) ?? 0;
  }

  /// Sube la racha si la ignoró; la resetea a 0 si interactuó.
  Future<void> registrarRespuesta({required bool interactuo}) async {
    final p = await SharedPreferences.getInstance();
    if (interactuo) {
      await p.setInt(_kIgnoradas, 0);
    } else {
      await p.setInt(_kIgnoradas, (p.getInt(_kIgnoradas) ?? 0) + 1);
    }
  }
}
