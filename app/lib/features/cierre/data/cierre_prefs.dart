/// Config del cierre del día (Push Capa 3a).
///
/// Hermano de `BriefingConfig`. Ya NO vive en SharedPreferences ni programa
/// alarma local: la fuente de verdad es el cerebro (tabla `config_rituales`),
/// que dispara el push. Acá queda solo el modelo; el estado lo maneja
/// `CierreConfigController` contra `RitualesRepository`.
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
