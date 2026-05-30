/// Config del briefing matutino (Push Capa 3a).
///
/// Ya NO vive en SharedPreferences ni programa una alarma local: la fuente
/// de verdad es el cerebro (tabla `config_rituales`), porque el scheduler
/// del servidor es el que dispara el push (los OEM matan las alarmas
/// locales). Acá queda solo el modelo; el estado lo maneja
/// `BriefingConfigController` contra `RitualesRepository`.
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
